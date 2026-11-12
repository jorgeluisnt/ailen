import SwiftUI

struct MiniPlayerView: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    var onTap: () -> Void

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.md) {
                if let track = playerManager.currentTrack {
                    // Sound Wave: round artwork inside a gradient progress ring.
                    artworkThumbnail
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .padding(4)
                        .overlay(MiniProgressRing(tokens: tokens))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .scaledFont(size: 15, weight: .semibold, relativeTo: .subheadline)
                            .lineLimit(1)
                            .foregroundColor(tokens.highlightColor)
                        subtitle
                    }
                } else {
                    Text("Nada en reproducción")
                        .scaledFont(size: 13, relativeTo: .footnote)
                        .foregroundColor(tokens.textSecondary)
                }

                Spacer()

                if playerManager.currentTrack != nil {
                    MiniElapsedTime(tokens: tokens)
                }

                trailingButton
            }
            .padding(.leading, DS.Spacing.sm)
            .padding(.trailing, DS.Spacing.sm)
            .frame(height: 64)
            // Fixed-height chrome: let text scale through the standard sizes but
            // clamp before the accessibility sizes clip the bar.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Abre el reproductor a pantalla completa")
    }

    @ViewBuilder
    private var artworkThumbnail: some View {
        if let url = playerManager.currentArtworkURL {
            AsyncCachedImage(url: url, targetSize: 42) {
                ArtworkPlaceholder(tokens: tokens, cornerRadius: 4)
            }
        } else {
            ArtworkPlaceholder(tokens: tokens, cornerRadius: 4)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        Text(playerManager.currentTrack?.artist ?? "")
            .scaledFont(size: 12, relativeTo: .caption)
            .lineLimit(1)
            .foregroundColor(tokens.textSecondary)
    }

    @ViewBuilder
    private var trailingButton: some View {
        HStack(spacing: 0) {
            Button {
                playerManager.togglePlayPause()
            } label: {
                Image(systemName: playerManager.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playerManager.isPlaying ? "Pausar" : "Reproducir")

            Button {
                Haptics.light()
                playerManager.nextTrack()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(playerManager.hasNext ? tokens.textPrimary : tokens.textSecondary.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!playerManager.hasNext)
            .accessibilityLabel("Siguiente canción")
        }
    }
}

/// Gradient ring showing playback progress around the mini-player artwork.
/// Its own view observing `clock`, so the 4 Hz position tick repaints only
/// the ring, never the whole bar.
private struct MiniProgressRing: View {
    @EnvironmentObject private var clock: PlaybackClock
    let tokens: DesignTokens

    var body: some View {
        let fraction = clock.duration > 0 ? min(max(clock.currentTime / clock.duration, 0), 1) : 0
        ZStack {
            Circle().stroke(tokens.textSecondary.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [tokens.accent, tokens.accentEnd ?? tokens.accent, tokens.accent],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

/// Elapsed time, also isolated from the bar's redraws.
private struct MiniElapsedTime: View {
    @EnvironmentObject private var clock: PlaybackClock
    let tokens: DesignTokens

    var body: some View {
        let seconds = Int(max(clock.currentTime, 0))
        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
            .scaledFont(size: 13, relativeTo: .footnote)
            .monospacedDigit()
            .foregroundColor(tokens.textPrimary)
            .accessibilityHidden(true)
    }
}
