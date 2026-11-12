import AVFoundation
import Foundation
import os.log

private let log = Logger(subsystem: "com.aria.music", category: "OutputSampleRate")

/// Legacy source-rate helper. A preferred sample rate is only a request;
/// the active route's effective rate must be read from `AVAudioSession` after
/// activation and after route changes. Playback no longer calls `apply`, so
/// this helper cannot force a USB DAC into a 44.1/48 kHz assumption.
enum OutputSampleRate {
    /// The legacy 44.1/48 kHz candidates, not a list of hardware limits.
    static let supported: [Double] = [44_100, 48_000]

    /// Legacy candidate rate for `sourceRate`, chosen by family rather than
    /// absolute distance: 88.2 kHz belongs to the 44.1 family even though
    /// 96 kHz is numerically closer to it than 44.1 is, because 88.2 → 44.1 is
    /// a clean 2:1 decimation while 88.2 → 48 is a messy ratio.
    ///
    /// A source is "in a family" when it's a clean integer multiple OR divisor
    /// of that family's base (so 22.05/88.2/176.4 → 44.1; 24/32/96/192 → 48).
    /// Anything else falls back to whichever base is numerically nearer.
    /// Returns nil for a non-positive/unknown rate (caller leaves the session alone).
    static func preferredRate(forSource sourceRate: Double) -> Double? {
        guard sourceRate > 0 else { return nil }
        let inFourtyFour = isCleanlyRelated(sourceRate, to: 44_100)
        let inFourtyEight = isCleanlyRelated(sourceRate, to: 48_000)
        if inFourtyFour && !inFourtyEight { return 44_100 }
        if inFourtyEight && !inFourtyFour { return 48_000 }
        // Both (e.g. an exact base) or neither → nearest base wins.
        return abs(sourceRate - 44_100) <= abs(sourceRate - 48_000) ? 44_100 : 48_000
    }

    /// True when `rate` is an integer multiple or an integer divisor of `base`
    /// (within a rounding tolerance), i.e. resampling between them is a clean
    /// power-of-two-ish ratio rather than an arbitrary conversion.
    private static func isCleanlyRelated(_ rate: Double, to base: Double) -> Bool {
        let tolerance = 1.0
        let up = rate / base                      // 88_200 / 44_100 = 2
        if abs(up - up.rounded()) * base < tolerance, up.rounded() >= 1 { return true }
        let down = base / rate                    // 48_000 / 24_000 = 2
        if abs(down - down.rounded()) * rate < tolerance, down.rounded() >= 1 { return true }
        return false
    }

    /// Reads the asset's audio sample rate, if it exposes one.
    static func sourceRate(of asset: AVAsset) async -> Double? {
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions) as [CMFormatDescription]?,
              let first = descriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee
        else { return nil }
        return asbd.mSampleRate > 0 ? asbd.mSampleRate : nil
    }

    /// Requests a candidate rate on the shared session. This does not report
    /// the effective output rate and is not used by the local playback path.
    static func apply(forSource sourceRate: Double,
                      session: AVAudioSession = .sharedInstance()) {
        guard let target = preferredRate(forSource: sourceRate) else { return }
        let current = session.sampleRate
        guard abs(current - target) > 1 else {
            // Logged (not silent) so field diagnosis can tell "already correct"
            // apart from "never ran" — silence used to mean either.
            log.notice("session already at \(target, privacy: .public) Hz for \(sourceRate, privacy: .public) Hz source — no change needed")
            return
        }
        do {
            try session.setPreferredSampleRate(target)
            // NOTE: the session applies a preferred rate on (re)activation, so
            // re-reading `session.sampleRate` here would report the OLD value
            // and look like a failure. Confirmation instead comes from the NEXT
            // track in the same family logging "already at <target>".
            log.notice("requested \(target, privacy: .public) Hz for \(sourceRate, privacy: .public) Hz source (was \(current, privacy: .public) Hz)")
        } catch {
            log.error("sample-rate request refused: \(error.localizedDescription, privacy: .public)")
        }
    }
}
