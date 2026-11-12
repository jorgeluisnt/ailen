import SwiftUI
import UIKit

/// What an external player (Apple Music, Spotify) is playing, plus how to
/// control it. Built by each service; drawn by the shared views below, so
/// both sources look and behave the same in Now Playing.
struct ExternalNowPlaying {
    enum Repeat { case off, all, one }

    let source: String
    let title: String
    let artist: String
    let artwork: UIImage?
    let isPlaying: Bool
    let shuffleOn: Bool
    let repeatState: Repeat
    let duration: TimeInterval
    /// Read on a timer: neither SDK publishes the position continuously.
    let position: () -> TimeInterval
    let note: String
    let playPause: () -> Void
    let next: () -> Void
    let previous: () -> Void
    let toggleShuffle: () -> Void
    let cycleRepeat: () -> Void
    let seek: (TimeInterval) -> Void

    /// The external source that was started last, if any.
    @MainActor
    static func active(appleMusic: AppleMusicService, spotify: SpotifyService) -> ExternalNowPlaying? {
        if spotify.isActiveSource, let model = spotify.nowPlayingModel { return model }
        if appleMusic.isActiveSource, let model = appleMusic.nowPlayingModel { return model }
        return nil
    }
}

/// Full Now Playing for an external source (iPad panel when `compact`).
struct ExternalNowPlayingView: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let model: ExternalNowPlaying
    var compact = false

    private var artworkSide: CGFloat {
        if compact { return 220 }
        return horizontalSizeClass == .regular ? 420 : min(290, UIScreen.main.bounds.height * 0.34)
    }

    var body: some View {
        let tokens = themeManager.tokens
        VStack(spacing: compact ? DS.Spacing.md : DS.Spacing.lg) {
            ExternalArtwork(image: model.artwork, corner: compact ? 18 : 20)
                .frame(width: artworkSide, height: artworkSide)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            VStack(spacing: 4) {
                Label(model.source, systemImage: "music.note")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tokens.highlightColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .glassSurface(in: Capsule())
                Text(model.title)
                    .font(compact ? .title3.weight(.bold) : .title.weight(.bold))
                    .foregroundColor(tokens.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(model.artist)
                    .font(compact ? .subheadline : .title3)
                    .foregroundColor(tokens.textSecondary)
                    .lineLimit(1)
            }

            ExternalSeekBar(model: model)
            ExternalTransportControls(model: model, compact: compact)

            Text(model.note)
                .font(.caption)
                .foregroundColor(tokens.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Elapsed · bar · total, refreshed twice a second; keeps the finger's value
/// while dragging and seeks on release.
struct ExternalSeekBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let model: ExternalNowPlaying
    @State private var dragValue: Double?

    var body: some View {
        let tokens = themeManager.tokens
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let duration = max(model.duration, 1)
            let current = dragValue ?? min(model.position(), duration)
            HStack(spacing: DS.Spacing.md) {
                Text(formatPlaybackTime(current))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tokens.textSecondary)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { current }, set: { dragValue = $0 }), in: 0...duration) { editing in
                    if !editing, let value = dragValue {
                        model.seek(value)
                        dragValue = nil
                    }
                }
                .tint(tokens.accent)
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue("\(formatPlaybackTime(current)) de \(formatPlaybackTime(model.duration))")
                Text(formatPlaybackTime(model.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(tokens.textSecondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Repeat · previous · play · next · shuffle, styled like the local player.
struct ExternalTransportControls: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let model: ExternalNowPlaying
    var compact = false

    var body: some View {
        let tokens = themeManager.tokens
        let skip: CGFloat = compact ? 44 : 52
        let play: CGFloat = compact ? 62 : 76
        HStack(spacing: compact ? DS.Spacing.sm : DS.Spacing.lg) {
            Button(action: model.cycleRepeat) {
                Image(systemName: model.repeatState == .one ? "repeat.1" : "repeat")
                    .font(.title3)
                    .foregroundColor(model.repeatState == .off ? tokens.textSecondary : tokens.accent)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Repetir")

            Button(action: model.previous) {
                Image(systemName: "backward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: skip, height: skip)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Canción anterior")

            Button(action: model.playPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: compact ? 24 : 30, weight: .bold))
                    .foregroundStyle(tokens.accentGradient)
                    .frame(width: play, height: play)
                    .glassSurface(in: Circle(), interactive: true)
                    .overlay(Circle().strokeBorder(tokens.accentGradient, lineWidth: 3))
            }
            .accessibilityLabel(model.isPlaying ? "Pausar" : "Reproducir")

            Button(action: model.next) {
                Image(systemName: "forward.end.fill")
                    .font(compact ? .title3 : .title2)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: skip, height: skip)
                    .glassSurface(in: Circle(), interactive: true)
            }
            .accessibilityLabel("Siguiente canción")

            Button(action: model.toggleShuffle) {
                Image(systemName: "shuffle")
                    .font(.title3)
                    .foregroundColor(model.shuffleOn ? tokens.accent : tokens.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.shuffleOn ? "Aleatorio activado" : "Aleatorio desactivado")
        }
        .buttonStyle(.plain)
    }
}

/// Mini player for an external source; tapping it opens the full player.
struct ExternalNowPlayingBar: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let model: ExternalNowPlaying
    var onTap: () -> Void = {}

    var body: some View {
        let tokens = themeManager.tokens
        HStack(spacing: DS.Spacing.md) {
            Button(action: onTap) {
                HStack(spacing: DS.Spacing.md) {
                    ExternalArtwork(image: model.artwork, corner: 8).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.title)
                            .font(DS.Typography.bodyEm)
                            .foregroundColor(tokens.highlightColor)
                            .lineLimit(1)
                        Text("\(model.source) · \(model.artist)")
                            .font(DS.Typography.caption)
                            .foregroundColor(tokens.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Abre el reproductor a pantalla completa")
            Button(action: model.playPause) {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.isPlaying ? "Pausar" : "Reproducir")
            Button(action: model.next) {
                Image(systemName: "forward.fill")
                    .font(.body)
                    .foregroundColor(tokens.textPrimary)
                    .frame(width: 40, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Siguiente canción")
        }
        .padding(.leading, DS.Spacing.sm)
        .padding(.trailing, DS.Spacing.xs)
        .padding(.vertical, 6)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .glassSurface(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: true)
    }
}

/// Artwork image or the placeholder.
struct ExternalArtwork: View {
    @EnvironmentObject private var themeManager: ThemeManager
    let image: UIImage?
    let corner: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ArtworkPlaceholder(tokens: themeManager.tokens, cornerRadius: corner)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .accessibilityHidden(true)
    }
}
