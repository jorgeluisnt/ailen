import SwiftUI

/// When the iPad layout (rail · Now Playing panel · content) is used:
/// regular width and landscape. Portrait iPad and iPhone keep the tab bar.
enum TabletLayout {
    static func isTablet(sizeClass: UserInterfaceSizeClass?, size: CGSize) -> Bool {
        sizeClass == .regular && size.width > size.height
    }
}

/// Sections of the iPad rail. Raw values are persisted.
enum TabletSection: String, CaseIterable, Identifiable {
    case home, library, playlists, favorites, videos, appleMusic, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Inicio"
        case .library: return "Biblioteca"
        case .playlists: return "Listas"
        case .favorites: return "Favoritos"
        case .videos: return "Videos"
        case .appleMusic: return "Apple Music"
        case .settings: return "Ajustes"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .library: return "books.vertical"
        case .playlists: return "music.note.list"
        case .favorites: return "heart"
        case .videos: return "film"
        case .appleMusic: return "music.note.house"
        case .settings: return "gearshape"
        }
    }
}

/// iPad landscape: icon rail, the always-visible Now Playing panel, content.
struct TabletRootView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var localLibraryManager: LocalLibraryManager
    @EnvironmentObject private var settingsManager: SettingsManager

    @AppStorage("tabletSection") private var sectionRaw = TabletSection.home.rawValue

    private var section: TabletSection {
        let stored = TabletSection(rawValue: sectionRaw) ?? .home
        // Apple Music switched off while it was selected → back to Home.
        return stored == .appleMusic && !settingsManager.appleMusicEnabled ? .home : stored
    }

    var body: some View {
        HStack(spacing: 0) {
            TabletRail(selection: Binding(get: { section }, set: { sectionRaw = $0.rawValue }))
                .frame(width: 80)
                .zIndex(1)
            NowPlayingPanel()
                .frame(width: 355)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home: HomeView(library: localLibraryManager)
        case .library: LibraryView(library: localLibraryManager)
        case .playlists: PlaylistsView()
        case .favorites: FavoritesView()
        case .videos: VideosView()
        case .appleMusic: AppleMusicView()
        case .settings: MoreView()
        }
    }
}

/// Narrow icon rail; the selected item gets the accent gradient.
struct TabletRail: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var nav: NavigationCoordinator
    @EnvironmentObject private var settingsManager: SettingsManager

    @Binding var selection: TabletSection

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            // App logo (a copy of the app icon: iOS can't load AppIcon as an image).
            Image("AppLogo")
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.bottom, DS.Spacing.lg)
                .accessibilityLabel("Ailen")

            ForEach([TabletSection.home, .library, .playlists, .favorites, .videos]
                    + (settingsManager.appleMusicEnabled ? [.appleMusic] : [])) { item in
                railButton(item.icon, item.title, selected: selection == item) { selection = item }
            }
            // The equalizer opens as a sheet, like from the player.
            railButton("slider.horizontal.3", "Ecualizador", selected: false) { nav.presentedSheet = .equalizer }

            Spacer()

            railButton(TabletSection.settings.icon, TabletSection.settings.title,
                       selected: selection == .settings) { selection = .settings }
        }
        .padding(.vertical, DS.Spacing.lg)
        .frame(maxHeight: .infinity)
        .background(tokens.surface.ignoresSafeArea())
    }

    private func railButton(_ icon: String, _ title: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: selected && icon == "heart" ? "heart.fill" : icon)
                .font(.title3.weight(selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : tokens.textSecondary)
                .frame(width: 48, height: 48)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tokens.accentGradient)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
