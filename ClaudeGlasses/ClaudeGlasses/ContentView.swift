import MWDATCore
import SwiftUI

struct ContentView: View {
  @ObservedObject var assistant: Assistant
  @AppStorage("didOnboard") private var didOnboard = false
  @State private var showSettings = false

  private var glasses: GlassesManager { assistant.glasses }
  private var voice: VoiceManager { assistant.voice }

  var body: some View {
    if didOnboard {
      home
    } else {
      OnboardingView { didOnboard = true }
    }
  }

  private var home: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          glassesCard
          if glasses.isStreaming || glasses.preview != nil { livePreview }
          modesSection
          askSection
          actionRow
          hintCard
          historySection
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
      }
      .scrollIndicators(.hidden)
      .background(Brand.bg.ignoresSafeArea())
      .toolbar(.hidden, for: .navigationBar)
      .sheet(isPresented: $showSettings) { SettingsView(assistant: assistant) }
      .alert("Что-то пошло не так", isPresented: errorBinding) {
        Button("OK") {
          glasses.errorMessage = nil
          voice.errorMessage = nil
        }
      } message: {
        Text(glasses.errorMessage ?? voice.errorMessage ?? "")
      }
      .onAppear {
        if assistant.apiKey.isEmpty { showSettings = true }
      }
    }
  }

  // MARK: Header

  private var header: some View {
    HStack(spacing: 10) {
      Image("WyroMark")
        .resizable().scaledToFit()
        .frame(height: 22)
        .accessibilityHidden(true)
      Text("WYRO")
        .font(.system(size: 24, weight: .semibold))
        .tracking(4)
        .foregroundStyle(Brand.text)
      Spacer()
      Button { showSettings = true } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(Brand.text)
          .frame(width: 44, height: 44)
          .background(Brand.surface, in: Circle())
          .overlay(Circle().stroke(Brand.border, lineWidth: 1))
      }
      .accessibilityLabel("Настройки")
    }
    .padding(.top, 8)
  }

  // MARK: Glasses status

  private var glassesState: (title: String, color: Color) {
    if !glasses.isRegistered {
      return glasses.registrationState == .registering
        ? ("Подключаю очки…", Brand.warning) : ("Очки не подключены", Brand.error)
    }
    if !glasses.hasActiveDevice { return ("Очки не рядом или выключены", Brand.warning) }
    return ("Очки подключены", Brand.success)
  }

  private var cameraChip: (String, Color) {
    switch glasses.streamState {
    case .streaming: return ("работает", Brand.success)
    case .starting, .waitingForDevice: return ("включается", Brand.warning)
    case .paused: return ("пауза", Brand.warning)
    default: return ("выкл", Brand.secondary)
    }
  }

  private var glassesCard: some View {
    Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Circle().fill(glassesState.color).frame(width: 9, height: 9)
              Text(glassesState.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.text)
            }
            Text("Ray-Ban Meta")
              .font(.system(size: 13))
              .foregroundStyle(Brand.secondary)
          }
          Spacer()
          Image(systemName: "eyeglasses")
            .font(.system(size: 38, weight: .light))
            .foregroundStyle(Brand.softBlue)
            .accessibilityHidden(true)
        }

        if glasses.isRegistered {
          HStack(spacing: 8) {
            StatusChip(title: "Камера", value: cameraChip.0, color: cameraChip.1)
            StatusChip(
              title: "Микрофон",
              value: voice.usingGlassesMic ? "очки" : "телефон",
              color: voice.usingGlassesMic ? Brand.success : Brand.secondary)
          }
        }

        if !glasses.isRegistered {
          Text("Откроется Meta AI — подтверди там и вернись сюда.")
            .font(.system(size: 13)).foregroundStyle(Brand.secondary)
          Button {
            glasses.register()
          } label: {
            Label("Подключить очки", systemImage: "link")
          }
          .buttonStyle(PrimaryButtonStyle())
        } else if !glasses.isStreaming {
          Button {
            Task { await assistant.start() }
          } label: {
            if glasses.isConnecting {
              HStack(spacing: 8) { ProgressView().tint(Brand.text); Text("Включаю камеру…") }
            } else {
              Label("Включить камеру и звук", systemImage: "video.fill")
            }
          }
          .buttonStyle(PrimaryButtonStyle())
          .disabled(glasses.isConnecting)
        }
      }
    }
  }

  private var livePreview: some View {
    ZStack(alignment: .topLeading) {
      if let image = glasses.preview {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        Brand.surface
      }
      // Shown only while the camera is really streaming.
      if glasses.isStreaming {
        HStack(spacing: 5) {
          Circle().fill(Brand.error).frame(width: 7, height: 7)
          Text("LIVE").font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(Brand.text)
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Brand.bg.opacity(0.75), in: Capsule())
        .padding(12)
      }
    }
    .frame(height: 200)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous).stroke(Brand.border, lineWidth: 1))
    .accessibilityLabel("Изображение с камеры очков")
  }

  // MARK: Modes

  private var modesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Режимы")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(Brand.text)
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
        ForEach(AssistantMode.allCases) { mode in
          modeTile(mode)
        }
      }
    }
  }

  private func modeTile(_ mode: AssistantMode) -> some View {
    let selected = assistant.mode == mode
    return Button {
      guard !selected else { return }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      assistant.switchMode(mode)
    } label: {
      HStack(spacing: 12) {
        Image(mode.iconAsset)
          .renderingMode(.template)
          .resizable().scaledToFit()
          .frame(width: 30, height: 30)
          .foregroundStyle(selected ? Brand.text : Brand.softBlue)
        VStack(alignment: .leading, spacing: 2) {
          Text(mode.title)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Brand.text)
          Text(mode.englishTitle)
            .font(.system(size: 12))
            .foregroundStyle(selected ? Brand.text.opacity(0.8) : Brand.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 68)
      .background(
        selected ? Brand.primary : Brand.surface,
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(selected ? Brand.primary : Brand.border, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Режим \(mode.title)")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  // MARK: Ask

  private var askTitle: String {
    if assistant.isThinking { return "WYRO думает…" }
    if voice.listeningToClient { return "Слушаю клиента…" }
    if voice.isSpeaking { return "Отвечаю…" }
    if voice.isListening { return assistant.alwaysListening ? "Жду «Клод, …»" : "Слушаю…" }
    return "Спроси WYRO"
  }

  private var askSection: some View {
    VStack(spacing: 12) {
      HStack(spacing: 18) {
        WaveBars(active: voice.isListening || voice.isSpeaking)
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          if voice.isSpeaking { voice.stopSpeaking() } else { voice.askOnce() }
        } label: {
          ZStack {
            Circle().fill(Brand.primary)
            Circle().stroke(Brand.softBlue.opacity(0.5), lineWidth: 2).padding(-6)
            if assistant.isThinking {
              ProgressView().tint(Brand.text).scaleEffect(1.3)
            } else {
              Image(systemName: voice.isSpeaking ? "stop.fill" : "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Brand.text)
            }
          }
          .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
        .disabled(assistant.isThinking)
        .accessibilityLabel(voice.isSpeaking ? "Остановить ответ" : "Задать вопрос голосом")
        WaveBars(active: voice.isListening || voice.isSpeaking, mirrored: true)
      }
      Text(askTitle)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Brand.text)
      Text(liveOrSubtitle)
        .font(.system(size: 13))
        .foregroundStyle(Brand.secondary)
        .multilineTextAlignment(.center)
        .lineLimit(3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }

  private var liveOrSubtitle: String {
    if voice.isListening && !voice.liveText.isEmpty { return "«\(voice.liveText)»" }
    return voice.isSpeaking ? "Нажми, чтобы остановить" : "Нажми и говори — я вижу то же, что ты"
  }

  // MARK: Actions

  private var actionRow: some View {
    HStack(spacing: 10) {
      Button {
        assistant.alwaysListening.toggle()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: assistant.alwaysListening ? "ear.fill" : "ear").font(.system(size: 20))
          Text("Всегда слушать")
        }
      }
      .buttonStyle(TileButtonStyle(active: assistant.alwaysListening))
      .accessibilityValue(assistant.alwaysListening ? "включено" : "выключено")

      modeActionButton

      Button {
        assistant.newConversation()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: "arrow.counterclockwise").font(.system(size: 20))
          Text("Новый разговор")
        }
      }
      .buttonStyle(TileButtonStyle())
    }
  }

  @ViewBuilder private var modeActionButton: some View {
    switch assistant.mode {
    case .barber:
      Button {
        assistant.startListeningToClient()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: "globe").font(.system(size: 20))
          Text(voice.listeningToClient ? "Слушаю…" : "Перевод")
        }
      }
      .buttonStyle(TileButtonStyle(active: voice.listeningToClient))
      .disabled(assistant.isThinking)
    case .artist:
      NavigationLink {
        NotebookView(notebook: assistant.notebook)
      } label: {
        VStack(spacing: 6) {
          Image(systemName: "music.note.list").font(.system(size: 20))
          Text("Блокнот · \(assistant.notebook.lines.count)")
        }
      }
      .buttonStyle(TileButtonStyle())
    default:
      Button {
        assistant.sendPicture.toggle()
      } label: {
        VStack(spacing: 6) {
          Image(systemName: assistant.sendPicture ? "camera.fill" : "camera").font(.system(size: 20))
          Text(assistant.sendPicture ? "Кадр: вкл" : "Кадр: выкл")
        }
      }
      .buttonStyle(TileButtonStyle(active: assistant.sendPicture))
    }
  }

  private var hintCard: some View {
    Card(padding: 14) {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "lightbulb")
          .foregroundStyle(Brand.softBlue)
        Text(assistant.mode.hint)
          .font(.system(size: 13))
          .foregroundStyle(Brand.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // MARK: History

  @ViewBuilder private var historySection: some View {
    if !assistant.log.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text("История")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(Brand.text)
        ForEach(assistant.log) { item in
          Card(padding: 14) {
            HStack(alignment: .top, spacing: 12) {
              if let image = item.image {
                Image(uiImage: image).resizable().scaledToFill()
                  .frame(width: 56, height: 56)
                  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              VStack(alignment: .leading, spacing: 6) {
                Text(item.question)
                  .font(.system(size: 15, weight: .semibold))
                  .foregroundStyle(Brand.text)
                if let answer = item.answer {
                  Text(answer)
                    .font(.system(size: 14))
                    .foregroundStyle(Brand.secondary)
                    .textSelection(.enabled)
                } else {
                  ProgressView().tint(Brand.softBlue)
                }
              }
            }
          }
        }
      }
    }
  }

  private var errorBinding: Binding<Bool> {
    Binding(
      get: { glasses.errorMessage != nil || voice.errorMessage != nil },
      set: { if !$0 { glasses.errorMessage = nil; voice.errorMessage = nil } }
    )
  }
}

// MARK: Onboarding

struct OnboardingView: View {
  var onFinish: () -> Void
  @State private var page = 0

  private let pages: [(icon: String, title: String, text: String)] = [
    ("eyeglasses", "Подключи очки", "WYRO работает с Ray-Ban Meta: камера и микрофон очков становятся глазами и ушами ассистента."),
    ("square.grid.2x2", "Выбери режим", "Vision для жизни и покупок, Барбер со стрижкой и переводом, Артист для музыки, Стилист для образа."),
    ("waveform", "Говори — я вижу то же, что ты", "Скажи «Клод, …» или нажми на микрофон. Ответ придёт голосом прямо в очки."),
  ]

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Image("WyroMark").resizable().scaledToFit().frame(height: 18)
        Text("WYRO").font(.system(size: 18, weight: .semibold)).tracking(3).foregroundStyle(Brand.text)
      }
      .padding(.top, 24)

      TabView(selection: $page) {
        ForEach(pages.indices, id: \.self) { i in
          VStack(spacing: 24) {
            Spacer()
            ZStack {
              Circle().fill(Brand.surface)
              Circle().stroke(Brand.border, lineWidth: 1)
              Image(systemName: pages[i].icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Brand.softBlue)
            }
            .frame(width: 180, height: 180)
            Text(pages[i].title)
              .font(.system(size: 28, weight: .semibold))
              .foregroundStyle(Brand.text)
              .multilineTextAlignment(.center)
            Text(pages[i].text)
              .font(.system(size: 16))
              .foregroundStyle(Brand.secondary)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 32)
            Spacer()
          }
          .tag(i)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .always))

      VStack(spacing: 14) {
        Button(page == pages.count - 1 ? "Начать" : "Дальше") {
          if page < pages.count - 1 {
            withAnimation { page += 1 }
          } else {
            onFinish()
          }
        }
        .buttonStyle(PrimaryButtonStyle())

        Text("by \(Brand.creator)")
          .font(.system(size: 12, weight: .medium))
          .tracking(1)
          .foregroundStyle(Brand.secondary)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
    .background(Brand.bg.ignoresSafeArea())
  }
}

struct SettingsView: View {
  @ObservedObject var assistant: Assistant
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          SecureField("sk-ant-…", text: $assistant.apiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
          Text("Ключ API Claude")
        } footer: {
          Text("Получи на console.anthropic.com → API Keys. Хранится только на этом iPhone.")
        }

        Section("Модель") {
          Picker("Модель", selection: $assistant.model) {
            Text("Sonnet — умнее").tag("claude-sonnet-5-5")
            Text("Haiku — быстрее и дешевле").tag("claude-haiku-5-5")
          }
          .pickerStyle(.inline)
          .labelsHidden()
        }

        Section {
          Toggle("Отправлять кадр с камеры", isOn: $assistant.sendPicture)
          Button("Новый разговор") { assistant.newConversation() }
        } footer: {
          Text("Каждый кадр — это платный запрос. Кадр отправляется только когда ты задаёшь вопрос.")
        }

        Section {
          LabeledContent("Создатель", value: Brand.creator)
          LabeledContent(
            "Версия",
            value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        } header: {
          Text("О приложении")
        }

        Section("Очки") {
          Button("Остановить камеру") { assistant.glasses.stop() }
          Button("Отключить очки от приложения", role: .destructive) {
            assistant.glasses.unregister()
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Brand.bg.ignoresSafeArea())
      .navigationTitle("Настройки")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
      }
    }
  }
}

struct NotebookView: View {
  @ObservedObject var notebook: Notebook

  var body: some View {
    List {
      if notebook.lines.isEmpty {
        Text("Пока пусто. Скажи: «Клод, запомни строчку …»").foregroundStyle(.secondary)
      }
      ForEach(notebook.lines) { line in
        VStack(alignment: .leading, spacing: 4) {
          Text(line.text)
          Text(line.date.formatted(date: .abbreviated, time: .shortened))
            .font(.caption).foregroundStyle(.secondary)
        }
        .contextMenu {
          Button("Скопировать") { UIPasteboard.general.string = line.text }
        }
      }
      .onDelete { notebook.remove(at: $0) }
    }
    .scrollContentBackground(.hidden)
    .background(Brand.bg.ignoresSafeArea())
    .navigationTitle("Блокнот строчек")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: notebook.asText) { Image(systemName: "square.and.arrow.up") }
          .disabled(notebook.lines.isEmpty)
      }
    }
  }
}
