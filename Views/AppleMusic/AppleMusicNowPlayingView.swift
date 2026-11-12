import MediaPlayer
import SwiftUI

/// Now Playing for Apple Music, used by the iPad panel (`compact`) and the
/// full-screen player. Same look as the local player; Apple plays the audio,
/// so there is no EQ, quality card or local queue.
struct AppleMusicNowPlayingView: View {
    @EnvironmentObject private var service: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var compact = false

    private var tokens: DesignTokens { themeManager.tokens }

    private var artworkSide: CGFloat {
        if compact { return 220 }
        return horizontalSizeClass == .regular ? 420 : min(290, UIScreen.main.bounds.height * 0.34)
    }

    var body: some View {
        VStack(spacing: compact ? DS.Spacing.md : DS.Spacing.lg) {
            AMArtwork(item: service.nowPlaying?.item, size: artworkSide, corner: compact ? 18 : 20, tokens: tokens)
                .frame(width: artworkSide, height: artworkSide)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            VStack(spacing: 4) {
                Label("Apple Music", systemImage: "music.note")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tokens.highlightColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .glassSurface(in: Capsule())
                Text(service.nowPlaying?.title ?? "")
                    .font(compact ? .title3.weight(.bold) : .title.weight(.bold))
                    .foregroundColor(tokens.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(service.nowPlaying?.artist ?? "")
                    .font(compact ? .subheadline : .title3)
                    .foregroundColor(tokens.textSecondary)
                    .lineLimit(1)
            }

            AppleMusicSeekBar()
            AppleMusicTransportControls(compact: compact)

            Text("Reproducido por Apple Music · sin ecualizador ni datos de calidad")
                .font(.caption)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Elapsed · bar · total. MediaPlayer doesn't publish the position, so it is
/// read twice a second; while dragging, the bar keeps the finger's value.
struct AppleMusicSeekBar: View {
    @EnvironmentObject private var service: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var dragValue: Double?

    var body: some View {
        let tokens = themeManager.tokens
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(service.duration, 1)
            let current = dragValue ?? min(service.currentTime, duration)
            HStack(spacing: DS.Spacing.md) {
                Text(formatPlaybackTime(current))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tokens.textSecondary)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { current }, set: { dragValue = $0 }),
                       in: 0...duration) { editing in
                    if !editing, let value = dragValue {
                        service.seek(to: value)
                        dragValue = nil
                    }
                }
                .tint(tokens.accent)
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue("\(formatPlaybackTime(current)) de \(formatPlaybackTime(service.duration))")
                Text(formatPlaybackTime(service.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tokens.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Repeat · previous · play · next · shuffle for Apple Music, styled like
/// `PlayerTransportControls`.
struct AppleMusicTransportControls: View {
    @EnvironmentObject private var service: AppleMusicService
    @EnvironmentObject private var themeManager: ThemeManager

    var compact = false

    var body: some View {
        let tokens = themeManager.tokens
        let skip: CGFloat = compact ? 44 : 52
        let play: CGFloat = compact ? 62 : 76
        HStack(spacing: compact ? DS.Spacing.sm : DS.Spacing.lg) {
            Button { service.cycleRepeat() } label: {
                Image(systemName: service.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundColor(service.repeatMode == .all || service.repeatMode == .one
                                     ? tokens.accent : tokens.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Repetir")

            Button { service.skipToPrevious() } label: {
                Image(systemName: "backward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: skip, height: skip)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Canción anterior")

            Button { service.togglePlayPause() } label: {
                Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 24 : 30, weight: .bold))
                    .foregroundStyle(tokens.accentGradient)
                    .frame(width: play, height: play)
                    .glassSurface(in: Circle(), interactive: true)
                    .overlay(Circle().strokeBorder(tokens.accentGradient, lineWidth: 3))
            }
            .accessibilityLabel(service.isPlaying ? "Pausar" : "Reproducir")

            Button { service.skipToNext() } label: {
                Image(systemName: "forward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: skip, height: skip)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Siguiente canción")

            Button { service.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(service.shuffleOn ? tokens.accent : tokens.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(service.shuffleOn ? "Aleatorio activado" : "Aleatorio desactivado")
        }
        .buttonStyle(.plain)
    }
}
