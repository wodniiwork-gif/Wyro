import Foundation
import SwiftUI

/// Lines the artist asked to remember («Клод, запомни строчку …»). Stored on the phone.
@MainActor
final class Notebook: ObservableObject {
  struct Line: Identifiable, Codable, Equatable {
    var id = UUID()
    let text: String
    let date: Date
  }

  @Published private(set) var lines: [Line] = []
  private let key = "notebookLines"

  init() {
    if let data = UserDefaults.standard.data(forKey: key),
      let saved = try? JSONDecoder().decode([Line].self, from: data)
    {
      lines = saved
    }
  }

  func add(_ text: String) {
    lines.insert(Line(text: text, date: Date()), at: 0)
    save()
  }

  func remove(at offsets: IndexSet) {
    lines.remove(atOffsets: offsets)
    save()
  }

  func removeLatest() -> Bool {
    guard !lines.isEmpty else { return false }
    lines.removeFirst()
    save()
    return true
  }

  /// All lines as one text, oldest first — handy for copying into Notes.
  var asText: String {
    lines.reversed().map(\.text).joined(separator: "\n")
  }

  private func save() {
    if let data = try? JSONEncoder().encode(lines) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }
}
