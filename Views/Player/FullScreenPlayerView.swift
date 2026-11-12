import SwiftUI

struct FullScreenPlayerView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appleMusic: AppleMusicService
    @EnvironmentObject private var nav: NavigationCoordinator

    var onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var sourceInfo: SourceAudioInfo?

    private let dragThreshold: CGFloat = 120

    var body: some View {
        ZStack {
            // Same backdrop as the iPad Now Playing panel.
            if showsAppleMusic {
                ArtworkBlurBackground(url: nil, image: appleMusic.nowPlayingArtwork, tokens: themeManager.tokens)
            } else {
                ArtworkBlurBackground(url: playerManager.currentArtworkURL, tokens: themeManager.tokens)
            }

            VStack(spacing: 0) {
                HStack {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundColor(themeManager.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassSurface(in: Circle(), interactive: true)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("Cerrar reproductor")

                    Spacer()

                    Text("Ahora suena")
                        .font(.headline)
                        .foregroundColor(themeManager.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    Spacer()

                    Button {
                        nav.presentedSheet = .queue
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.headline)
                            .foregroundColor(playerManager.queue.isEmpty
                                             ? themeManager.textSecondary
                                             : themeManager.textPrimary)
                            .frame(width: 44, height: 44)
                            .glassSurface(in: Circle(), interactive: true)
                            // A real count badge: anchored to the frame's top-
                            // trailing corner and inset, so multi-digit counts
                            // grow leftward and stay inside the 44pt tap target
                            // instead of spilling into the neighbouring control.
                            .overlay(alignment: .topTrailing) {
                                if !playerManager.queue.isEmpty {
                                    Text(playerManager.queue.count > 99 ? "99+" : "\(playerManager.queue.count)")
                                        .scaledFont(size: 9, weight: .bold, relativeTo: .caption2)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Capsule().fill(themeManager.theme.accentColor))
                                        .padding([.top, .trailing], 2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(playerManager.queue.isEmpty ? "Mostrar cola" : "Mostrar cola, \(playerManager.queue.count) a continuación")
                    // The local queue doesn't apply to Apple Music.
                    .opacity(showsAppleMusic ? 0 : 1)
                    .disabled(showsAppleMusic)
                }
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, 20)

                if showsAppleMusic {
                    AppleMusicNowPlayingView()
                } else if let track = playerManager.currentTrack {
                    artworkSection(track: track)
                    trackInfoSection(track: track)
                    PlayerSeekBar()
                        .padding(.bottom, DS.Spacing.sm)
                    PlayerTransportControls()
                        .padding(.bottom, DS.Spacing.lg)
                    PlayerSecondaryControls(track: track, onNothingLeft: onDismiss)
                    queueHint
                    if playerManager.playbackState == .loading {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(themeManager.theme.accentColor)
                            .padding(.top, 8)
                    }
                } else {
                    Spacer()
                    Text("Nada en reproducción")
                        .foregroundColor(themeManager.textSecondary)
                }

                Spacer()
            }
            // iPad: keep controls at a readable width instead of edge to edge.
            .frame(maxWidth: 560)
            .padding(.horizontal, DS.Spacing.xl)
        }
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    if value.translation.height > dragThreshold {
                        onDismiss()
                    } else if value.translation.height < -dragThreshold * 0.6 && !showsAppleMusic {
                        nav.presentedSheet = .queue  // Sound Wave: swipe up for the queue
                    }
                    withAnimation(.spring(response: 0.3)) {
                        dragOffset = 0
                    }
                }
        )
        .task(id: playerManager.currentTrack?.id) {
            sourceInfo = nil
            guard let url = playerManager.currentTrack?.localFileURL else { return }
            sourceInfo = await SourceAudioInfo.inspect(url)
        }
    }

    /// Apple Music was started last: show and control it instead.
    private var showsAppleMusic: Bool { appleMusic.isActiveSource && appleMusic.nowPlaying != nil }

    // MARK: - Artwork

    private func artworkSection(track: Track) -> some View {
        // Larger on iPad; smaller with accessibility text sizes so the
        // controls still fit on an iPhone screen.
        // On iPhone also capped to ~1/3 of the screen height, so the whole
        // player fits on small phones (SE: 227 pt) without scrolling.
        let side: CGFloat = horizontalSizeClass == .regular ? 420
            : dynamicTypeSize.isAccessibilitySize ? 160
            : min(290, UIScreen.main.bounds.height * 0.34)

        return Group {
            if let url = playerManager.currentArtworkURL {
                AsyncCachedImage(url: url, targetSize: side) {
                    ArtworkPlaceholder(tokens: themeManager.tokens, cornerRadius: DS.Radius.md)
                }
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: themeManager.theme.accentColor.opacity(0.25), radius: 24, y: 10)
            } else {
                ArtworkPlaceholder(tokens: themeManager.tokens, cornerRadius: 20)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .padding(.bottom, DS.Spacing.lg)
        .accessibilityHidden(true)  // decorative; title and artist follow
    }

    // MARK: - Track Info

    private func trackInfoSection(track: Track) -> some View {
        VStack(spacing: 4) {
            // Sound Wave order: artist above, large title below.
            Text(track.artist)
                .font(.title3)
                .foregroundColor(themeManager.textSecondary)
                .lineLimit(1)

            Text(track.title)
                .font(.title.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(themeManager.textPrimary)

            if let album = track.album, !album.isEmpty {
                Text(album)
                    .font(.subheadline)
                    .foregroundColor(themeManager.textSecondary)
                    .lineLimit(1)
            }

            PlayerQualityCard(track: track, sourceInfo: sourceInfo)
                .padding(.top, DS.Spacing.sm)
        }
        .padding(.bottom, DS.Spacing.lg)
    }

    /// Sound Wave's "swipe up for playlist", here opening the queue. Also a
    /// button, so it works without the gesture (VoiceOver, Switch Control).
    private var queueHint: some View {
        Button { nav.presentedSheet = .queue } label: {
            VStack(spacing: 2) {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                Text("Desliza hacia arriba para ver la cola")
                    .font(.caption2)
            }
            .foregroundColor(themeManager.textSecondary)
            .padding(.top, DS.Spacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mostrar cola")
    }
}
