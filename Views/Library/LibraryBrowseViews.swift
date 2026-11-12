import SwiftUI

/// What the Library shows. Raw values are persisted (`@AppStorage`).
enum LibraryScope: String, CaseIterable, Identifiable {
    case songs, albums, artists, genres, folders

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .songs: return "Canciones"
        case .albums: return "Álbumes"
        case .artists: return "Artistas"
        case .genres: return "Géneros"
        case .folders: return "Carpetas"
        }
    }
}

/// Glass capsule with one pill per scope; the selected one is filled with
/// the accent gradient (Sound Wave).
struct LibraryScopeBar: View {
    @Binding var scope: LibraryScope
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibraryScope.allCases) { item in
                Button {
                    Haptics.selection()
                    scope = item
                } label: {
                    Text(item.displayName)
                        .font(DS.Typography.captionStrong)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundColor(scope == item ? .white : tokens.textSecondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background {
                            if scope == item { Capsule().fill(tokens.accentGradient) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == item ? [.isSelected] : [])
            }
        }
        .padding(4)
        .glassSurface(in: Capsule())
    }
}

/// Square artwork with title and subtitle: one album or artist in the grid.
struct CollectionTile: View {
    let collection: LibraryCollection
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if let url = collection.artworkTrack?.artworkURL {
                        AsyncCachedImage(url: url, targetSize: 160) {
                            ArtworkPlaceholder(tokens: tokens, cornerRadius: 12)
                        }
                        .aspectRatio(contentMode: .fill)
                    } else {
                        ArtworkPlaceholder(tokens: tokens, cornerRadius: 12)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(collection.title)
                .font(DS.Typography.bodyEm)
                .foregroundColor(tokens.textPrimary)
                .lineLimit(1)
            Text(collection.subtitle)
                .font(DS.Typography.caption)
                .foregroundColor(tokens.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Three-column grid of albums or artists (adapts to more columns on iPad).
struct CollectionGrid<Destination: View>: View {
    let collections: [LibraryCollection]
    let tokens: DesignTokens
    let destination: (LibraryCollection) -> Destination

    var body: some View {
        // Collections are A→Z, so the first one per letter is the jump target.
        let anchors = AlphabetIndex.anchors(collections, letter: { AlphabetIndex.letter(for: $0.title) },
                                            id: { AnyHashable($0.id) })
        let showIndex = anchors.count > 1
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: DS.Spacing.md)],
                          spacing: DS.Spacing.lg) {
                    ForEach(collections) { collection in
                        NavigationLink { destination(collection) } label: {
                            CollectionTile(collection: collection, tokens: tokens)
                        }
                        .buttonStyle(.plain)
                        .id(collection.id)
                    }
                }
                .padding(DS.Spacing.lg)
                .padding(.trailing, showIndex ? AlphabetIndexBar.width : 0)
            }
            .overlay(alignment: .trailing) {
                if showIndex {
                    AlphabetIndexBar(available: Set(anchors.keys), tokens: tokens) { letter in
                        if let id = anchors[letter] { proxy.scrollTo(id, anchor: .top) }
                    }
                    .padding(.vertical, DS.Spacing.lg)
                }
            }
        }
    }
}

/// Genre chips: the selected one gets the accent gradient, the rest glass.
struct GenreChips: View {
    let genres: [LibraryCollection]
    @Binding var selection: String?
    let tokens: DesignTokens

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Spacing.sm)],
                  spacing: DS.Spacing.sm) {
            ForEach(genres) { genre in
                let selected = selection == genre.id
                Button {
                    Haptics.selection()
                    selection = genre.id
                } label: {
                    Text(genre.title)
                        .font(DS.Typography.bodyEm)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundColor(selected ? .white : tokens.textPrimary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tokens.accentGradient)
                            }
                        }
                        .glassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(genre.title), \(genre.subtitle)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

/// "Reproducir" (gradient) and "Aleatorio" (glass) for a collection.
struct PlayShuffleButtons: View {
    let tokens: DesignTokens
    let onPlay: () -> Void
    let onShuffle: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(action: onPlay) {
                Label("Reproducir", systemImage: "play.fill")
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Capsule().fill(tokens.accentGradient))
            }
            Button(action: onShuffle) {
                Label("Aleatorio", systemImage: "shuffle")
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .glassSurface(in: Capsule(), interactive: true)
            }
        }
        .buttonStyle(.plain)
    }
}
