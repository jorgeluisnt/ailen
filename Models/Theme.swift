import SwiftUI
import UIKit

struct AppTheme: Identifiable, Equatable {
    let id: String
    let name: String
    let accentColor: Color
    /// End colour of the accent gradient (play button ring, chips).
    var gradientEnd: Color
    /// Secondary highlight: mini-player title, links, section titles.
    var highlight: Color

    init(id: String, name: String, accentColor: Color, gradientEnd: Color? = nil, highlight: Color? = nil) {
        self.id = id
        self.name = name
        self.accentColor = accentColor
        self.gradientEnd = gradientEnd ?? accentColor
        self.highlight = highlight ?? accentColor
    }
}

extension AppTheme {
    static let allThemes: [AppTheme] = [
        // Sound Wave UI kit: purple → blue gradient, magenta highlight.
        AppTheme(id: "soundwave", name: "Sound Wave", accentColor: RGB.soundWavePurple.color,
                 gradientEnd: RGB.soundWaveBlue.color, highlight: RGB.soundWaveMagenta.color),
        AppTheme(id: "blue",    name: "Azul",       accentColor: Color(red: 0.35, green: 0.65, blue: 0.95)),
        AppTheme(id: "orange",  name: "Ámbar",      accentColor: Color(red: 0.98, green: 0.60, blue: 0.20)),
        AppTheme(id: "teal",    name: "Océano",     accentColor: Color(red: 0.25, green: 0.80, blue: 0.75)),
        AppTheme(id: "mono",    name: "Mono",       accentColor: Color(red: 0.85, green: 0.85, blue: 0.85)),
        AppTheme(id: "rose",    name: "Rosa",       accentColor: Color(red: 0.95, green: 0.35, blue: 0.50)),
        AppTheme(id: "forest",  name: "Bosque",     accentColor: Color(red: 0.30, green: 0.80, blue: 0.45)),
    ]

    static let `default` = allThemes[0]

    /// The user-edited theme ("Personalizado").
    static func custom(accent: RGB, gradientEnd: RGB) -> AppTheme {
        AppTheme(id: "custom", name: "Personalizado", accentColor: accent.color,
                 gradientEnd: gradientEnd.color, highlight: accent.color)
    }
}

/// An sRGB colour that can be stored as hex and mixed. Used by the editable
/// theme, whose dark surfaces are derived from one background colour.
struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1); self.g = min(max(g, 0), 1); self.b = min(max(b, 0), 1)
    }

    init(_ r: Int, _ g: Int, _ b: Int) {
        self.init(r: Double(r) / 255, g: Double(g) / 255, b: Double(b) / 255)
    }

    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        self.init((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    }

    /// From a `ColorPicker` value, in sRGB. `nil` if it can't be converted.
    init?(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }

    var hex: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// Darkens toward black (keeping the hue) until white text has ≥ 10:1
    /// contrast, which also keeps the derived secondary text ≥ 4.5:1.
    func darkenedForLightText(maxLuminance: Double = 0.05) -> RGB {
        var c = self
        while c.luminance > maxLuminance { c = c.mixed(with: .black, 0.05) }
        return c
    }

    static let black = RGB(0, 0, 0)
    static let white = RGB(255, 255, 255)
    // Sound Wave UI kit, sampled from its screens.
    static let soundWaveBackground = RGB(0x1D, 0x24, 0x2C)
    static let soundWavePurple = RGB(0x8C, 0x39, 0xEB)
    static let soundWaveBlue = RGB(0x47, 0x56, 0xD5)
    static let soundWaveMagenta = RGB(0xD8, 0x51, 0xDC)
}
