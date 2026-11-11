import SwiftUI
import UIKit

// MARK: - Colors

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Palette {
    /// App background.
    static let neutral = Color(hex: 0x121317)
    /// Card and panel fill, one step above the background.
    static let surface = Color(hex: 0x1C1D22)
    /// Inset wells inside a card (stat cells, map frames).
    static let well = Color(hex: 0x15161A)
    /// 1px borders.
    static let hairline = Color(hex: 0x2C2D33)

    static let primary = Color(hex: 0xD4B996)
    static let secondary = Color(hex: 0xC6A679)
    static let tertiary = Color(hex: 0xE6D5C3)
    static let destructive = Color(hex: 0xF2A9A5)

    static let textPrimary = Color(hex: 0xF1F1F4)
    static let textSecondary = Color(hex: 0x9A9BA3)
    static let textMuted = Color(hex: 0x62636B)
    /// Text and icons placed on a cream fill.
    static let onPrimary = Color(hex: 0x1A1509)
}

// MARK: - Layout

enum Metrics {
    static let corner: CGFloat = 4
    static let hairline: CGFloat = 1
    static let gutter: CGFloat = 16
    static let cardPadding: CGFloat = 14
}

// MARK: - Type

/// Uses the bundled font when it is present and falls back to a system
/// design that is close, so screens still look right before fonts are added.
enum Typeface {
    static func headline(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        let name = weight == .bold ? "SpaceGrotesk-Bold" : "SpaceGrotesk-Medium"
        return custom(name, size: size) ?? .system(size: size, weight: weight)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .regular ? "Geist-Regular" : "Geist-Medium"
        return custom(name, size: size) ?? .system(size: size, weight: weight)
    }

    static func label(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font {
        let name = weight == .bold ? "JetBrainsMono-Bold" : "JetBrainsMono-Medium"
        return custom(name, size: size)
            ?? .system(size: size, weight: weight, design: .monospaced)
    }

    private static func custom(_ name: String, size: CGFloat) -> Font? {
        UIFont(name: name, size: size) == nil ? nil : .custom(name, size: size)
    }
}

// MARK: - Reusable pieces

/// Small mono caps label used above values and as section tags.
struct MonoLabel: View {
    let text: String
    var color: Color = Palette.textMuted
    var size: CGFloat = 10

    init(_ text: String, color: Color = Palette.textMuted, size: CGFloat = 10) {
        self.text = text
        self.color = color
        self.size = size
    }

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.label(size))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

struct CardStyle: ViewModifier {
    var fill: Color = Palette.surface

    func body(content: Content) -> some View {
        content
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(Palette.hairline, lineWidth: Metrics.hairline)
            )
    }
}

extension View {
    func card(fill: Color = Palette.surface) -> some View {
        modifier(CardStyle(fill: fill))
    }
}

enum LapsyButtonKind {
    case primary, secondary, inverted, outlined
}

struct LapsyButtonStyle: ButtonStyle {
    var kind: LapsyButtonKind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.label(13, weight: .bold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.corner))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.corner)
                    .strokeBorder(border, lineWidth: Metrics.hairline)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .inverted: Palette.onPrimary
        case .secondary, .outlined: Palette.textPrimary
        }
    }

    private var background: Color {
        switch kind {
        case .primary: Palette.primary
        case .secondary: Palette.well
        case .inverted: Palette.textPrimary
        case .outlined: .clear
        }
    }

    private var border: Color {
        switch kind {
        case .secondary, .outlined: Palette.hairline
        case .primary, .inverted: .clear
        }
    }
}
