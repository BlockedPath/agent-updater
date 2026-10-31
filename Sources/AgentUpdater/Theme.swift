import AppKit
import SwiftUI

/// A color theme. "System" uses macOS colors and materials; the others are popular editor themes
/// with their published palettes. Every colored element in the app reads from `Palette`, which
/// points at the current theme (the window is rebuilt when the theme changes).
struct Theme: Identifiable, Hashable {
    let id: String
    let name: String
    /// Forces dark (true) or light (false); nil follows the Appearance setting.
    let dark: Bool?
    /// Window background; nil keeps the translucent system material.
    let background: Color?
    let surface: Color
    let border: Color
    /// Body text; nil keeps the system label color.
    let text: Color?
    let accent: Color   // coding agents, "All", working
    let accent2: Color  // orchestrators, Discover
    let accent3: Color  // agent systems
    let success: Color
    let warning: Color  // updates available
    let danger: Color
    let info: Color
    let caution: Color

    /// The swatch row shown in Settings.
    var swatches: [Color] { [background ?? Color(nsColor: .windowBackgroundColor), accent, accent2, success, warning] }

    static let system = Theme(
        id: "system", name: "System", dark: nil, background: nil,
        surface: Color(nsColor: .controlBackgroundColor).opacity(0.8), border: .primary.opacity(0.08), text: nil,
        accent: .blue, accent2: .purple, accent3: .pink, success: .green, warning: .orange,
        danger: .red, info: .teal, caution: .yellow)

    static let all: [Theme] = [
        .system,
        Theme(id: "tokyo-night", name: "Tokyo Night", dark: true, background: Color(hex: 0x1A1B26),
              surface: Color(hex: 0x24283B), border: Color(hex: 0x414868), text: Color(hex: 0xC0CAF5),
              accent: Color(hex: 0x7AA2F7), accent2: Color(hex: 0xBB9AF7), accent3: Color(hex: 0x7DCFFF),
              success: Color(hex: 0x9ECE6A), warning: Color(hex: 0xFF9E64), danger: Color(hex: 0xF7768E),
              info: Color(hex: 0x73DACA), caution: Color(hex: 0xE0AF68)),
        Theme(id: "catppuccin-mocha", name: "Catppuccin Mocha", dark: true, background: Color(hex: 0x1E1E2E),
              surface: Color(hex: 0x313244), border: Color(hex: 0x45475A), text: Color(hex: 0xCDD6F4),
              accent: Color(hex: 0x89B4FA), accent2: Color(hex: 0xCBA6F7), accent3: Color(hex: 0xF5C2E7),
              success: Color(hex: 0xA6E3A1), warning: Color(hex: 0xFAB387), danger: Color(hex: 0xF38BA8),
              info: Color(hex: 0x94E2D5), caution: Color(hex: 0xF9E2AF)),
        Theme(id: "catppuccin-latte", name: "Catppuccin Latte", dark: false, background: Color(hex: 0xEFF1F5),
              surface: Color(hex: 0xE6E9EF), border: Color(hex: 0xCCD0DA), text: Color(hex: 0x4C4F69),
              accent: Color(hex: 0x1E66F5), accent2: Color(hex: 0x8839EF), accent3: Color(hex: 0xEA76CB),
              success: Color(hex: 0x40A02B), warning: Color(hex: 0xFE640B), danger: Color(hex: 0xD20F39),
              info: Color(hex: 0x179299), caution: Color(hex: 0xDF8E1D)),
        Theme(id: "dracula", name: "Dracula", dark: true, background: Color(hex: 0x282A36),
              surface: Color(hex: 0x343746), border: Color(hex: 0x44475A), text: Color(hex: 0xF8F8F2),
              accent: Color(hex: 0xBD93F9), accent2: Color(hex: 0xFF79C6), accent3: Color(hex: 0x8BE9FD),
              success: Color(hex: 0x50FA7B), warning: Color(hex: 0xFFB86C), danger: Color(hex: 0xFF5555),
              info: Color(hex: 0x8BE9FD), caution: Color(hex: 0xF1FA8C)),
        Theme(id: "nord", name: "Nord", dark: true, background: Color(hex: 0x2E3440),
              surface: Color(hex: 0x3B4252), border: Color(hex: 0x4C566A), text: Color(hex: 0xECEFF4),
              accent: Color(hex: 0x88C0D0), accent2: Color(hex: 0xB48EAD), accent3: Color(hex: 0x81A1C1),
              success: Color(hex: 0xA3BE8C), warning: Color(hex: 0xD08770), danger: Color(hex: 0xBF616A),
              info: Color(hex: 0x8FBCBB), caution: Color(hex: 0xEBCB8B)),
        Theme(id: "gruvbox-dark", name: "Gruvbox Dark", dark: true, background: Color(hex: 0x282828),
              surface: Color(hex: 0x3C3836), border: Color(hex: 0x504945), text: Color(hex: 0xEBDBB2),
              accent: Color(hex: 0x83A598), accent2: Color(hex: 0xD3869B), accent3: Color(hex: 0x8EC07C),
              success: Color(hex: 0xB8BB26), warning: Color(hex: 0xFE8019), danger: Color(hex: 0xFB4934),
              info: Color(hex: 0x8EC07C), caution: Color(hex: 0xFABD2F)),
        Theme(id: "one-dark", name: "One Dark", dark: true, background: Color(hex: 0x282C34),
              surface: Color(hex: 0x2F343F), border: Color(hex: 0x3E4451), text: Color(hex: 0xABB2BF),
              accent: Color(hex: 0x61AFEF), accent2: Color(hex: 0xC678DD), accent3: Color(hex: 0x56B6C2),
              success: Color(hex: 0x98C379), warning: Color(hex: 0xD19A66), danger: Color(hex: 0xE06C75),
              info: Color(hex: 0x56B6C2), caution: Color(hex: 0xE5C07B)),
        Theme(id: "rose-pine", name: "Rosé Pine", dark: true, background: Color(hex: 0x191724),
              surface: Color(hex: 0x1F1D2E), border: Color(hex: 0x26233A), text: Color(hex: 0xE0DEF4),
              accent: Color(hex: 0x9CCFD8), accent2: Color(hex: 0xC4A7E7), accent3: Color(hex: 0xEBBCBA),
              success: Color(hex: 0x31748F), warning: Color(hex: 0xF6C177), danger: Color(hex: 0xEB6F92),
              info: Color(hex: 0x9CCFD8), caution: Color(hex: 0xF6C177)),
        Theme(id: "solarized-dark", name: "Solarized Dark", dark: true, background: Color(hex: 0x002B36),
              surface: Color(hex: 0x073642), border: Color(hex: 0x0E4B59), text: Color(hex: 0x93A1A1),
              accent: Color(hex: 0x268BD2), accent2: Color(hex: 0x6C71C4), accent3: Color(hex: 0xD33682),
              success: Color(hex: 0x859900), warning: Color(hex: 0xCB4B16), danger: Color(hex: 0xDC322F),
              info: Color(hex: 0x2AA198), caution: Color(hex: 0xB58900)),
        Theme(id: "solarized-light", name: "Solarized Light", dark: false, background: Color(hex: 0xFDF6E3),
              surface: Color(hex: 0xEEE8D5), border: Color(hex: 0xDDD6C1), text: Color(hex: 0x586E75),
              accent: Color(hex: 0x268BD2), accent2: Color(hex: 0x6C71C4), accent3: Color(hex: 0xD33682),
              success: Color(hex: 0x859900), warning: Color(hex: 0xCB4B16), danger: Color(hex: 0xDC322F),
              info: Color(hex: 0x2AA198), caution: Color(hex: 0xB58900)),
        Theme(id: "github-dark", name: "GitHub Dark", dark: true, background: Color(hex: 0x0D1117),
              surface: Color(hex: 0x161B22), border: Color(hex: 0x30363D), text: Color(hex: 0xE6EDF3),
              accent: Color(hex: 0x2F81F7), accent2: Color(hex: 0xA371F7), accent3: Color(hex: 0xDB61A2),
              success: Color(hex: 0x3FB950), warning: Color(hex: 0xD29922), danger: Color(hex: 0xF85149),
              info: Color(hex: 0x39C5CF), caution: Color(hex: 0xD29922)),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? .system }
}

/// The current theme's colors, for views to read directly.
enum Palette {
    static var theme: Theme = .named(UserDefaults.standard.string(forKey: Pref.theme) ?? "system")

    static var surface: Color { theme.surface }
    static var border: Color { theme.border }
    static var accent: Color { theme.accent }
    static var accent2: Color { theme.accent2 }
    static var accent3: Color { theme.accent3 }
    static var success: Color { theme.success }
    static var warning: Color { theme.warning }
    static var danger: Color { theme.danger }
    static var info: Color { theme.info }
    static var caution: Color { theme.caution }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Applies a theme to a window's content: forced appearance, background, text and accent.
struct ThemedWindow: ViewModifier {
    let theme: Theme

    func body(content: Content) -> some View {
        content
            .containerBackground(theme.background.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.thinMaterial), for: .window)
            .foregroundStyle(theme.text.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
            .tint(theme.accent)
    }
}

/// A theme choice in Settings: name plus its palette.
struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(theme.swatches.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: index == 0 ? 16 : 12, height: index == 0 ? 16 : 12)
                            .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                    }
                }
                Text(theme.name).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(selected ? 0.9 : 0.35), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? theme.accent : .clear, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
