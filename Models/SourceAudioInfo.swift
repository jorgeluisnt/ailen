import AVFoundation
import Foundation

/// Properties reported by the audio track in the source file. A missing value
/// stays unknown; neither the file extension nor its size is used as a proxy.
struct SourceAudioInfo: Equatable {
    let codec: String?
    let sampleRate: Double?
    let bitDepth: UInt32?

    static func inspect(_ url: URL) async -> SourceAudioInfo? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let descriptions = try? await track.load(.formatDescriptions),
              let description = descriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
        else { return nil }
        return SourceAudioInfo(formatID: asbd.mFormatID,
                               sampleRate: asbd.mSampleRate,
                               bitDepth: asbd.mBitsPerChannel,
                               formatFlags: asbd.mFormatFlags)
    }

    /// Lossless compressed tracks report `mBitsPerChannel == 0`; CoreAudio
    /// stores their source bit depth in `mFormatFlags` (same values for ALAC
    /// and FLAC). Lossy codecs have no source bit depth.
    init(formatID: AudioFormatID, sampleRate: Double, bitDepth: UInt32, formatFlags: AudioFormatFlags = 0) {
        switch formatID {
        case kAudioFormatFLAC: codec = "FLAC"
        case kAudioFormatAppleLossless: codec = "ALAC"
        case kAudioFormatLinearPCM: codec = "PCM"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        case kAudioFormatMPEG4AAC: codec = "AAC"
        default: codec = nil
        }
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : nil
        if bitDepth > 0 {
            self.bitDepth = bitDepth
        } else if formatID == kAudioFormatFLAC || formatID == kAudioFormatAppleLossless {
            switch formatFlags {
            case kAppleLosslessFormatFlag_16BitSourceData: self.bitDepth = 16
            case kAppleLosslessFormatFlag_20BitSourceData: self.bitDepth = 20
            case kAppleLosslessFormatFlag_24BitSourceData: self.bitDepth = 24
            case kAppleLosslessFormatFlag_32BitSourceData: self.bitDepth = 32
            default: self.bitDepth = nil
            }
        } else {
            self.bitDepth = nil
        }
    }

    var displayText: String {
        let rate = sampleRate.map { String(format: "%g kHz", $0 / 1_000) } ?? "No disponible"
        let bits = bitDepth.map { "\($0) bits" } ?? "No disponible"
        return "Archivo: \(codec ?? "No disponible") · \(bits) / \(rate)"
    }
}
