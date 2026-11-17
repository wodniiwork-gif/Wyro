import SwiftUI

/// WYRO design tokens (from the approved brand board).
enum Brand {
  static let name = "WYRO"
  static let creator = "Art Anzhelii"

  // Colours
  static let bg = Color(hex: 0x080D20)        // основной фон
  static let surface = Color(hex: 0x151D30)   // карточки и панели
  static let elevated = Color(hex: 0x222D44)  // всплывающие элементы
  static let primary = Color(hex: 0x1463FF)   // кнопки и активные элементы
  static let softBlue = Color(hex: 0x83ACFF)  // иконки и подсветка
  static let text = Color(hex: 0xF4F6FA)      // заголовки и основной текст
  static let secondary = Color(hex: 0x9CAAC2) // подписи и описания
  static let border = Color(hex: 0x29344A)    // разделители и границы
  static let success = Color(hex: 0x22C55E)
  static let warning = Color(hex: 0xF59E0B)
  static let error = Color(hex: 0xEF4444)

  // Kept for older code
  static let accent = primary

  // Shape
  static let cardRadius: CGFloat = 20
  static let buttonRadius: CGFloat = 24
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1)
  }
}

// MARK: Mode presentation

extension AssistantMode {
  /// Asset name of the mode icon (template image, tinted in code).
  var iconAsset: String {
    switch self {
    case .general: return "ModeVision"
    case .barber: return "ModeBarber"
    case .artist: return "ModeArtist"
    case .stylist: return "ModeStylist"
    }
  }

  var englishTitle: String {
    switch self {
    case .general: return "Vision"
    case .barber: return "Barber"
    case .artist: return "Artist"
    case .stylist: return "Style"
    }
  }
}

// MARK: Reusable components

/// Dark rounded card with a thin border.
struct Card<Content: View>: View {
  var padding: CGFloat = 16
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Brand.surface, in: RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
          .stroke(Brand.border, lineWidth: 1))
  }
}

/// Solid blue button.
struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 16, weight: .semibold))
      .foregroundStyle(Brand.text)
      .frame(maxWidth: .infinity, minHeight: 50)
      .background(Brand.primary, in: RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}

/// Dark tile button with an icon on top (Камера / Перевод / …).
struct TileButtonStyle: ButtonStyle {
  var active = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(active ? Brand.text : Brand.secondary)
      .frame(maxWidth: .infinity, minHeight: 64)
      .background(
        active ? Brand.primary.opacity(0.22) : Brand.surface,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(active ? Brand.primary : Brand.border, lineWidth: active ? 1.5 : 1))
      .opacity(configuration.isPressed ? 0.75 : 1)
  }
}

/// Small status chip: ● Камера · работает
struct StatusChip: View {
  let title: String
  let value: String
  let color: Color

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(title).foregroundStyle(Brand.secondary)
      Text(value).foregroundStyle(Brand.text)
    }
    .font(.system(size: 12, weight: .medium, design: .monospaced))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(Brand.elevated, in: Capsule())
    .accessibilityElement(children: .combine)
  }
}

/// Animated bars shown next to the mic while listening.
struct WaveBars: View {
  var active: Bool
  var mirrored = false
  @State private var phase = false

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<6, id: \.self) { i in
        let index = mirrored ? 5 - i : i
        Capsule()
          .fill(Brand.softBlue.opacity(0.35 + Double(index) * 0.1))
          .frame(width: 3, height: barHeight(index))
      }
    }
    .frame(height: 40)
    .animation(
      active ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default,
      value: phase
    )
    .onAppear { phase.toggle() }
    .onChange(of: active) { _, _ in phase.toggle() }
    .accessibilityHidden(true)
  }

  private func barHeight(_ i: Int) -> CGFloat {
    let base: [CGFloat] = [6, 12, 20, 14, 26, 10]
    guard active else { return 4 + base[i] * 0.25 }
    return phase ? base[i] + 10 : base[(i + 3) % 6]
  }
}
