import SwiftUI
import Combine

@MainActor final class ThemeManager: ObservableObject {
    @Published var theme: AppTheme = .default
    @Published var isDarkMode: Bool = true
    /// Base colour of the dark palette; every dark surface derives from it.
    @Published private(set) var darkBackground: RGB = .soundWaveBackground

    private let settings: SettingsManager

    init(settings: SettingsManager) {
        self.settings = settings
        self.isDarkMode = settings.isDarkMode
        if settings.selectedThemeID == "custom" {
            self.theme = .custom(accent: RGB(hex: settings.customAccentHex) ?? .soundWavePurple,
                                 gradientEnd: RGB(hex: settings.customAccentEndHex) ?? .soundWaveBlue)
        } else if let t = AppTheme.allThemes.first(where: { $0.id == settings.selectedThemeID }) {
            self.theme = t
        }
        if let base = RGB(hex: settings.customBackgroundHex) {
            self.darkBackground = base.darkenedForLightText()
        }
    }

    // MARK: - Editable theme

    /// Sets a free accent colour (`end == false`) or gradient end colour and
    /// switches to the "Personalizado" theme, starting from the current one.
    func setCustomAccent(_ color: Color, end: Bool = false) {
        guard let rgb = RGB(color) else { return }
        var start = RGB(theme.accentColor) ?? .soundWavePurple
        var finish = RGB(theme.gradientEnd) ?? .soundWaveBlue
        if end { finish = rgb } else { start = rgb }
        settings.customAccentHex = start.hex
        settings.customAccentEndHex = finish.hex
        theme = .custom(accent: start, gradientEnd: finish)
        settings.setTheme("custom")
    }

    /// Sets the dark background, darkened if needed so text stays legible.
    func setDarkBackground(_ color: Color) {
        guard let rgb = RGB(color) else { return }
        darkBackground = rgb.darkenedForLightText()
        settings.customBackgroundHex = darkBackground.hex
        settings.save()
    }

    /// Back to Sound Wave: theme, accent and background.
    func resetCustomTheme() {
        darkBackground = .soundWaveBackground
        settings.customBackgroundHex = ""
        settings.customAccentHex = ""
        settings.customAccentEndHex = ""
        selectTheme(.default)
    }

    func selectTheme(_ theme: AppTheme) {
        self.theme = theme
        settings.setTheme(theme.id)
    }

    func toggleDarkMode() {
        isDarkMode.toggle()
        settings.isDarkMode = isDarkMode
        settings.save()
    }

    // MARK: - Token API (preferred)

    var tokens: DesignTokens {
        DesignTokens(isDark: isDarkMode, accent: theme.accentColor, accentEnd: theme.gradientEnd,
                     highlight: theme.highlight, base: darkBackground)
    }

    /// Reasonable default tokens for views that need a `DesignTokens`
    /// value without access to a live `ThemeManager` instance (e.g. a
    /// shared view's default parameter value). Matches `AppTheme.default`
    /// in dark mode, which is the app's default appearance.
    static var fallbackTokens: DesignTokens {
        DesignTokens(isDark: true, accent: AppTheme.default.accentColor,
                     accentEnd: AppTheme.default.gradientEnd, highlight: AppTheme.default.highlight)
    }

    // MARK: - Legacy convenience (kept for existing call-sites)

    var background: Color { tokens.background }
    var surface: Color { tokens.surface }
    var textPrimary: Color { tokens.textPrimary }
    var textSecondary: Color { tokens.textSecondary }
    var dividerColor: Color { tokens.dividerColor }
}

/// Strongly-typed design tokens that depend on the current theme & mode.
struct DesignTokens {
    let isDark: Bool
    let accent: Color
    var accentEnd: Color? = nil
    var highlight: Color? = nil
    /// Dark-mode base colour (editable theme). Light mode ignores it.
    var base: RGB = .soundWaveBackground

    /// Accent → gradient end, left to right (Sound Wave buttons and chips).
    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentEnd ?? accent], startPoint: .leading, endPoint: .trailing)
    }

    /// Mini-player title, links and section titles.
    var highlightColor: Color { highlight ?? accent }

    // Dark palette derived from `base`. With Sound Wave's #1D242C the card
    // mix gives #252F38, the kit's header and card colour.
    var background: Color {
        isDark ? base.color : Color(red: 0.98, green: 0.98, blue: 0.99)
    }

    var surface: Color {
        isDark ? base.mixed(with: .white, 0.03).color : Color(white: 0.96)
    }

    /// Slightly tinted surface used for "card" backgrounds.
    var cardSurface: Color {
        isDark ? base.mixed(with: .white, 0.05).color : Color.white
    }

    var textPrimary: Color {
        isDark ? Color.white : Color(red: 0.07, green: 0.07, blue: 0.08)
    }

    var textSecondary: Color {
        // Light 0.45→0.40 lifts secondary text on the ~0.96 background from
        // ~4.35:1 to ~5.2:1, clearing the WCAG AA 4.5:1 threshold for small
        // text. Dark (0.62 on ~0.10) is already ~6:1.
        // Dark: base mixed 55% toward white (~#9DA1A5 on #1D242C, ~7:1).
        isDark ? base.mixed(with: .white, 0.55).color : Color(white: 0.40)
    }

    var dividerColor: Color {
        isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var hairline: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }

    /// Soft accent wash for active rows / pills.
    var accentSubtle: Color {
        accent.opacity(0.18)
    }
}
