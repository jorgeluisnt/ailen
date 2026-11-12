import SwiftUI

/// iPhone "Más" tab: the sections that don't fit in the tab bar. Picking one
/// shows it full screen (each has its own navigation); tapping "Más" in the
/// tab bar comes back here.
struct MoreHubView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var settingsManager: SettingsManager
    let open: (AppTab) -> Void

    private var tokens: DesignTokens { themeManager.tokens }

    private var entries: [(tab: AppTab, icon: String, title: String, detail: String)] {
        var list: [(AppTab, String, String, String)] = [
            (.videos, "film", "Videos", "Tus videos MP4, MOV y M4V"),
        ]
        if settingsManager.appleMusicEnabled {
            list.append((.appleMusic, "music.note.house", "Apple Music", "Tu biblioteca de Apple Music"))
        }
        if settingsManager.spotifyEnabled {
            list.append((.spotify, "dot.radiowaves.left.and.right", "Spotify", "Controla la app de Spotify"))
        }
        list.append((.more, "gearshape", "Ajustes", "Ecualizador, tema, pantalla e integraciones"))
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                tokens.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                            if index > 0 {
                                Divider().background(tokens.hairline).padding(.leading, 64)
                            }
                            Button { open(entry.tab) } label: { row(entry) }
                                .buttonStyle(.plain)
                        }
                    }
                    .glassSurface(in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Más")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func row(_ entry: (tab: AppTab, icon: String, title: String, detail: String)) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: entry.icon)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tokens.accentGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.textPrimary)
                Text(entry.detail)
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(tokens.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
