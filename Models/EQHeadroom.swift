import Foundation

/// Headroom for the graphic EQ. Cascaded filters add in dB, so the curve's
/// peak is the max over frequency of the summed band responses (RBJ peaking
/// biquads, the shape AUNBandEQ's parametric bands follow). A preamp of
/// `-peak` keeps a full-scale signal from clipping because of the EQ boost.
enum EQHeadroom {
    /// AUNBandEQ's default bandwidth, used by the graphic bands.
    static let graphicBandwidthOctaves: Float = 0.5

    /// Highest gain (dB, ≥ 0) of the combined curve between 20 Hz and 20 kHz.
    static func peakGain(frequencies: [Float], gains: [Float],
                         bandwidthOctaves: Float = graphicBandwidthOctaves,
                         sampleRate: Double = 48_000) -> Float {
        let bands = zip(frequencies, gains).filter { $0.1 != 0 }
        guard !bands.isEmpty else { return 0 }
        // ponytail: 1/48-octave grid plus the band centres; finer only if a
        // measured curve ever peaks between grid points by more than ~0.1 dB.
        let grid = (0...480).map { 20 * pow(2, Double($0) / 48) }
        let probes = grid + frequencies.map(Double.init)
        var peak = 0.0
        for f in probes where f <= 20_000 && f < sampleRate / 2 {
            let sum = bands.reduce(0.0) {
                $0 + peakingResponseDB(at: f, centre: Double($1.0), gainDB: Double($1.1),
                                       bandwidth: Double(bandwidthOctaves), sampleRate: sampleRate)
            }
            peak = max(peak, sum)
        }
        return Float(peak)
    }

    /// Preamp (dB, ≤ 0) that cancels the curve's peak boost.
    static func preamp(frequencies: [Float], gains: [Float]) -> Float {
        -peakGain(frequencies: frequencies, gains: gains)
    }

    /// Magnitude in dB of an RBJ peaking EQ biquad at `f`.
    static func peakingResponseDB(at f: Double, centre: Double, gainDB: Double,
                                  bandwidth: Double, sampleRate: Double) -> Double {
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * centre / sampleRate
        let alpha = sin(w0) * sinh(log(2) / 2 * bandwidth * w0 / sin(w0))
        let c = cos(w0)
        let b = (1 + alpha * a, -2 * c, 1 - alpha * a)
        let d = (1 + alpha / a, -2 * c, 1 - alpha / a)
        let w = 2 * Double.pi * f / sampleRate
        func mag2(_ k: (Double, Double, Double)) -> Double {
            let re = k.0 + k.1 * cos(w) + k.2 * cos(2 * w)
            let im = -(k.1 * sin(w) + k.2 * sin(2 * w))
            return re * re + im * im
        }
        return 10 * log10(mag2(b) / mag2(d))
    }
}
