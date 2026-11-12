import AVFoundation
import XCTest
@testable import Ailen

final class SourceAudioInfoTests: XCTestCase {
    func testVerifiedFormatAndRate() {
        let info = SourceAudioInfo(formatID: kAudioFormatLinearPCM, sampleRate: 96_000, bitDepth: 24)
        XCTAssertEqual(info.displayText, "Archivo: PCM · 24 bits / 96 kHz")
    }

    /// AVFoundation reports mBitsPerChannel = 0 for FLAC/ALAC; depth is in the flags.
    func testLosslessBitDepthComesFromFormatFlags() {
        let flac = SourceAudioInfo(formatID: kAudioFormatFLAC, sampleRate: 192_000, bitDepth: 0,
                                   formatFlags: kAppleLosslessFormatFlag_24BitSourceData)
        XCTAssertEqual(flac.displayText, "Archivo: FLAC · 24 bits / 192 kHz")
        let alac = SourceAudioInfo(formatID: kAudioFormatAppleLossless, sampleRate: 44_100, bitDepth: 0,
                                   formatFlags: kAppleLosslessFormatFlag_16BitSourceData)
        XCTAssertEqual(alac.displayText, "Archivo: ALAC · 16 bits / 44.1 kHz")
    }

    func testLossyCodecHasNoBitDepth() {
        let mp3 = SourceAudioInfo(formatID: kAudioFormatMPEGLayer3, sampleRate: 44_100, bitDepth: 0)
        XCTAssertNil(mp3.bitDepth)
    }

    func testUnknownPropertiesRemainUnavailable() {
        let info = SourceAudioInfo(formatID: 0, sampleRate: 0, bitDepth: 0)
        XCTAssertEqual(info.displayText, "Archivo: No disponible · No disponible / No disponible")
    }
}
