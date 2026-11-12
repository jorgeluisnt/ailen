import SwiftUI

/// Fine control over playback speed and pitch. Speed works like a record, so it
/// moves pitch with it; the pitch slider is an offset on top of that. At offset
/// 0 no pitch processing runs at all, so the sound stays clean.
struct SpeedPitchSheet: View {
    @EnvironmentObject private var playerManager: PlayerManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss

    private var tokens: DesignTokens { themeManager.tokens }

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: DS.Spacing.xl) {
                        speedRow
                        pitchRow
                        netPitchLine
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle("Velocidad y tono")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Rows

    private var speedRow: some View {
        tuningRow(
            title: "Velocidad",
            readout: String(format: "%.2f×", playerManager.playbackRate),
            value: Binding(get: { playerManager.playbackRate },
                           set: { playerManager.setPlaybackRate($0) }),
            range: PlaybackTuning.speedRange,
            step: PlaybackTuning.speedStep,
            defaultValue: PlaybackTuning.defaultSpeed,
            accessibilityUnit: "veces la velocidad"
        )
    }

    private var pitchRow: some View {
        tuningRow(
            title: "Tono",
            readout: pitchReadout,
            value: Binding(get: { playerManager.playbackPitch },
                           set: { playerManager.setPlaybackPitch($0) }),
            range: PlaybackTuning.pitchRange,
            step: PlaybackTuning.pitchStep,
            defaultValue: PlaybackTuning.defaultPitch,
            accessibilityUnit: "semitonos"
        )
    }

    private var pitchReadout: String {
        let pitch = playerManager.playbackPitch
        return pitch == 0 ? "0.0 st" : String(format: "%+.1f st", pitch)
    }

    /// The combined result, because with two controls moving pitch the answer
    /// to "how far is this from the recording?" isn't on either slider.
    private var netPitchLine: some View {
        let net = PlaybackTuning.netSemitones(speed: playerManager.playbackRate,
                                              pitch: playerManager.playbackPitch)
        // Rounded to the readout's precision so it can't print "-0.0".
        let shown = (net * 10).rounded() / 10
        let text = shown == 0
            ? "Suena en el tono original"
            : String(format: "Suena %+.1f semitonos respecto al original", shown)
        return Text(text)
            .font(DS.Typography.caption)
            .foregroundColor(tokens.textSecondary)
            .monospacedDigit()
            .frame(maxWidth: .infinity)
    }

    private func tuningRow(title: String,
                           readout: String,
                           value: Binding<Float>,
                           range: ClosedRange<Float>,
                           step: Float,
                           defaultValue: Float,
                           accessibilityUnit: String) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            HStack {
                Text(title)
                    .font(DS.Typography.bodyEm)
                    .foregroundColor(tokens.textPrimary)
                Text(readout)
                    .font(DS.Typography.body)
                    .monospacedDigit()
                    .foregroundColor(value.wrappedValue == defaultValue ? tokens.textSecondary : tokens.accent)
                Spacer()
                Button("Restablecer") {
                    Haptics.light()
                    value.wrappedValue = defaultValue
                }
                .font(DS.Typography.caption)
                .disabled(value.wrappedValue == defaultValue)
                .accessibilityLabel("Restablecer \(title.lowercased())")
            }
            HStack(spacing: DS.Spacing.sm) {
                stepButton(systemName: "minus", label: "Disminuir \(title.lowercased())") {
                    value.wrappedValue = value.wrappedValue - step
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Slider(value: value, in: range, step: step)
                    .tint(tokens.accent)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(readout) \(accessibilityUnit)")

                stepButton(systemName: "plus", label: "Aumentar \(title.lowercased())") {
                    value.wrappedValue = value.wrappedValue + step
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
        }
    }

    /// Slider steps are too small to land on by dragging, so each end nudges by
    /// exactly one.
    private func stepButton(systemName: String, label: String,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(tokens.surface))
        }
        .buttonStyle(.plain)
        .foregroundColor(tokens.textPrimary)
        .accessibilityLabel(label)
    }
}
