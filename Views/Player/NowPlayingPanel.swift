import SwiftUI

/// iPad landscape: the always-visible Now Playing column with its queue.
/// The background is the current artwork, blurred, under Liquid Glass.
struct NowPlayingPanel: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appleMusic: AppleMusicService

    @State private var sourceInfo: SourceAudioInfo?
    @State private var editMode: EditMode = .inactive

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            Text("AHORA SUENA")
                .font(.footnote.weight(.semibold))
                .tracking(2)
                .foregroundColor(tokens.textPrimary)
                .padding(.top, DS.Spacing.lg)
                .accessibilityAddTraits(.isHeader)

            if showsAppleMusic {
                AppleMusicNowPlayingView(compact: true)
                Spacer()
            } else if let track = playerManager.currentTrack {
                artwork
                VStack(spacing: 2) {
                    Text(track.title)
                        .font(.title3.weight(.bold))
                        .foregroundColor(tokens.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(track.artist)
                        .font(.subheadline)
                        .foregroundColor(tokens.textSecondary)
                        .lineLimit(1)
                }
                PlayerQualityCard(track: track, sourceInfo: sourceInfo)
                PlayerSeekBar()
                PlayerTransportControls(compact: true)
                PlayerSecondaryControls(track: track, spacing: 14)
                queueSection
            } else {
                Spacer()
                VStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(tokens.textSecondary)
                    Text("Nada en reproducción")
                        .font(DS.Typography.bodyEm)
                        .foregroundColor(tokens.textSecondary)
                    Text("Elige una canción de tu biblioteca.")
                        .font(DS.Typography.caption)
                        .foregroundColor(tokens.textSecondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .frame(maxHeight: .infinity)
        // Artwork and glass reach the screen edges (under the status bar and
        // home indicator); only the content respects the safe area.
        .background {
            if showsAppleMusic {
                ArtworkBlurBackground(url: nil, image: appleMusic.nowPlayingArtwork, tokens: tokens)
            } else {
                ArtworkBlurBackground(url: playerManager.currentArtworkURL, tokens: tokens)
            }
        }
        .environment(\.editMode, $editMode)
        .task(id: playerManager.currentTrack?.id) {
            sourceInfo = nil
            guard let url = playerManager.currentTrack?.localFileURL else { return }
            sourceInfo = await SourceAudioInfo.inspect(url)
        }
    }

    /// Apple Music was started last: show and control it instead.
    private var showsAppleMusic: Bool { appleMusic.isActiveSource && appleMusic.nowPlaying != nil }

    private var artwork: some View {
        Group {
            if let url = playerManager.currentArtworkURL {
                AsyncCachedImage(url: url, targetSize: 220) {
                    ArtworkPlaceholder(tokens: tokens, cornerRadius: 18)
                }
                .aspectRatio(contentMode: .fill)
            } else {
                ArtworkPlaceholder(tokens: tokens, cornerRadius: 18)
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityHidden(true)
    }

    private var queueSection: some View {
        VStack(spacing: DS.Spacing.xs) {
            HStack {
                Text("TU COLA")
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundColor(tokens.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !playerManager.queue.isEmpty {
                    QueueEditButton(editMode: $editMode)
                        .font(DS.Typography.captionStrong)
                        .foregroundColor(tokens.highlightColor)
                }
            }
            if playerManager.queue.isEmpty {
                Text("La cola está vacía")
                    .font(DS.Typography.caption)
                    .foregroundColor(tokens.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, DS.Spacing.sm)
            } else {
                QueueListContent()
                    .padding(.horizontal, -DS.Spacing.lg)  // rows carry their own insets
            }
        }
        .frame(maxHeight: .infinity)
    }
}
