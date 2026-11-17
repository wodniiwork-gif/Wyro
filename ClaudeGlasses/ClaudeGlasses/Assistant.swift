import Combine
import Foundation
import UIKit

/// Glues it together: question from the voice → frame from the glasses →
/// Claude → answer spoken in the glasses. Also handles voice commands
/// (switch mode, translator, notebook) before anything goes to Claude.
@MainActor
final class Assistant: ObservableObject {
  struct Exchange: Identifiable {
    let id = UUID()
    let question: String
    var answer: String?
    let image: UIImage?
  }

  @Published var log: [Exchange] = []
  @Published var isThinking = false
  @Published var alwaysListening = false {
    didSet { alwaysListening ? voice.startContinuous() : voice.stopContinuous() }
  }
  @Published var sendPicture = true
  @Published var mode: AssistantMode =
    AssistantMode(rawValue: UserDefaults.standard.string(forKey: "mode") ?? "") ?? .general
  {
    didSet {
      UserDefaults.standard.set(mode.rawValue, forKey: "mode")
      newConversation()  // a fresh start so the old topic doesn't leak in
    }
  }
  @Published var apiKey: String = Keychain.load("apiKey") {
    didSet { Keychain.save(apiKey, for: "apiKey") }
  }
  @Published var model: String = UserDefaults.standard.string(forKey: "model") ?? "claude-sonnet-5-5" {
    didSet { UserDefaults.standard.set(model, forKey: "model") }
  }

  let glasses = GlassesManager()
  let voice = VoiceManager()
  let notebook = Notebook()
  private var history: [ClaudeClient.Turn] = []
  private var bag = Set<AnyCancellable>()

  init() {
    voice.onQuestion = { [weak self] question in
      Task { await self?.ask(question) }
    }
    voice.onClientSpeech = { [weak self] phrase in
      Task { await self?.translateFromClient(phrase) }
    }
    glasses.prepareAudioBeforeStream = { [weak self] in
      await self?.voice.prepareGlassesAudio()
    }
    // Re-publish changes of the child objects so SwiftUI refreshes.
    glasses.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    voice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    notebook.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
  }

  /// Connect everything: permissions, audio through the glasses, camera.
  func start() async {
    guard await voice.requestPermissions() else { return }
    await glasses.start()
    if !glasses.isStreaming {
      // Camera may still be starting; audio is set up anyway.
      await voice.prepareGlassesAudio()
    }
  }

  // MARK: Questions

  func ask(_ question: String) async {
    guard !isThinking else { return }
    if handleCommand(question) { return }

    let image = wantsPicture(question) ? glasses.frames.latest() : nil
    await send(
      question: question,
      image: image,
      system: mode.systemPrompt,
      maxTokens: mode == .artist ? 600 : 450,
      useHistory: true
    ) { [weak self] answer in
      self?.voice.speak(answer)
    }
  }

  /// In artist mode the camera is off by default (lyrics don't need it), unless
  /// the question is about something visible.
  private func wantsPicture(_ question: String) -> Bool {
    guard sendPicture else { return false }
    if mode.picturesByDefault { return true }
    let lower = question.lowercased()
    let visual = ["смотри", "видишь", "это", "здесь", "тут", "экран", "микшер", "плагин", "место", "кадр", "фото"]
    return visual.contains { lower.contains($0) }
  }

  // MARK: Voice commands

  /// Returns true if the phrase was a command and was handled here.
  private func handleCommand(_ question: String) -> Bool {
    let lower = question.lowercased()
    let short = lower.count < 45

    // Mode switch: «Клод, режим барбера / артиста / обычный режим».
    if short && lower.contains("режим") {
      if lower.contains("барбер") || lower.contains("стрижк") { switchMode(.barber); return true }
      if lower.contains("артист") || lower.contains("музык") || lower.contains("рэп") { switchMode(.artist); return true }
      if lower.contains("обычн") || lower.contains("базов") { switchMode(.general); return true }
      if lower.contains("стилист") || lower.contains("стил") || lower.contains("шмот") { switchMode(.stylist); return true }
    }

    // Translator, client → me: «Клод, слушай клиента» / «что он говорит».
    let listenPhrases = ["слушай клиента", "послушай клиента", "что он говорит", "что она говорит",
                         "что он сказал", "что она сказала", "переведи клиента"]
    if short && listenPhrases.contains(where: { lower.contains($0) }) {
      startListeningToClient()
      return true
    }

    // Translator, me → client: «Клод, скажи клиенту: …».
    let sayPrefixes = ["скажи клиенту", "скажи ему", "скажи ей", "переведи на английский", "как сказать"]
    if let prefix = sayPrefixes.first(where: { lower.hasPrefix($0) }) {
      let phrase = text(after: prefix, in: question)
      if phrase.isEmpty {
        voice.speak("Что сказать клиенту?")
      } else {
        Task { await translateForClient(phrase, outLoud: prefix != "как сказать") }
      }
      return true
    }

    // Notebook: «Клод, запомни строчку …».
    let savePrefixes = ["запомни строчку", "запиши строчку", "сохрани строчку", "запомни строку", "запиши строку"]
    if let prefix = savePrefixes.first(where: { lower.hasPrefix($0) }) {
      let line = text(after: prefix, in: question)
      if line.isEmpty {
        voice.speak("Какую строчку записать?")
      } else {
        notebook.add(line)
        log.insert(Exchange(question: "📝 \(line)", answer: "Записал в блокнот", image: nil), at: 0)
        voice.speak("Записал.")
      }
      return true
    }
    if short && (lower.contains("прочитай строчки") || lower.contains("мои строчки") || lower.contains("прочитай строки")) {
      let last = notebook.lines.prefix(5).reversed().map(\.text)
      voice.speak(last.isEmpty ? "Блокнот пока пустой." : last.joined(separator: ". "))
      return true
    }
    if short && (lower.contains("удали последнюю строчку") || lower.contains("удали последнюю строку")) {
      voice.speak(notebook.removeLatest() ? "Удалил последнюю строчку." : "Блокнот пустой.")
      return true
    }

    return false
  }

  func switchMode(_ newMode: AssistantMode) {
    mode = newMode
    voice.speak(newMode.announcement)
  }

  /// Text after a command prefix, without leading punctuation («скажи клиенту: …»).
  private func text(after prefix: String, in original: String) -> String {
    String(original.dropFirst(prefix.count))
      .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines))
  }

  // MARK: Translator

  func startListeningToClient() {
    voice.speak("Слушаю клиента.") { [weak self] in
      self?.voice.listenToClient()
    }
  }

  private func translateFromClient(_ phrase: String) async {
    await send(
      question: phrase,
      image: nil,
      system: AssistantMode.clientToRussianPrompt,
      maxTokens: 200,
      useHistory: false,
      label: "🇬🇧 \(phrase)"
    ) { [weak self] russian in
      self?.voice.speak(russian)
    }
  }

  func translateForClient(_ phrase: String, outLoud: Bool) async {
    await send(
      question: phrase,
      image: nil,
      system: AssistantMode.russianToClientPrompt,
      maxTokens: 200,
      useHistory: false,
      label: "🗣 \(phrase)"
    ) { [weak self] english in
      // Out loud through the phone speaker so the client hears it,
      // or in the glasses when you only want to know how to say it.
      self?.voice.speak(english, language: "en-GB", outLoud: outLoud)
    }
  }

  // MARK: Sending

  private func send(
    question: String,
    image: UIImage?,
    system: String,
    maxTokens: Int,
    useHistory: Bool,
    label: String? = nil,
    onAnswer: @escaping (String) -> Void
  ) async {
    guard !isThinking else { return }
    isThinking = true
    let entry = Exchange(question: label ?? question, answer: nil, image: image)
    log.insert(entry, at: 0)
    func setAnswer(_ text: String) {
      if let i = log.firstIndex(where: { $0.id == entry.id }) { log[i].answer = text }
    }

    var client = ClaudeClient(apiKey: apiKey, model: model, systemPrompt: system)
    client.maxTokens = maxTokens
    do {
      let answer = try await client.ask(
        question: question, image: image, history: useHistory ? history : [])
      setAnswer(answer)
      if useHistory { remember(question: question, answer: answer) }
      isThinking = false
      onAnswer(answer)
    } catch {
      let message = error.localizedDescription
      setAnswer("⚠️ \(message)")
      isThinking = false
      voice.speak("Не получилось. \(message)")
    }
  }

  func newConversation() {
    history.removeAll()
    log.removeAll()
  }

  /// Keep recent exchanges as text so follow-up questions make sense.
  private func remember(question: String, answer: String) {
    history.append(.init(role: "user", text: question))
    history.append(.init(role: "assistant", text: answer))
    let limit = mode == .general ? 12 : 20
    if history.count > limit { history.removeFirst(history.count - limit) }
  }
}
