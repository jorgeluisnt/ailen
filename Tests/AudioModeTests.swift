import XCTest
@testable import Ailen

/// Directo / Ecualizador mode, graphic-EQ headroom and local playback failures.
@MainActor
final class AudioModeTests: XCTestCase {
    private let curve: [Float] = [3, 2, 1, 0, 0, 0, 0, 1, 2, 3]

    // MARK: - EQController mode

    func test_directKeepsCurveAndDisablesProcessing() {
        let eq = EQController()
        eq.apply(curve)
        XCTAssertEqual(eq.setDirect(true), .becameDisabled)
        XCTAssertFalse(eq.isEnabled)
        XCTAssertEqual(eq.bands, curve, "Directo must not lose the user's curve")
        XCTAssertEqual(eq.setDirect(false), .becameEnabled)
        XCTAssertTrue(eq.isEnabled)
    }

    func test_directWithFlatCurveReportsNoChange() {
        let eq = EQController()
        XCTAssertEqual(eq.setDirect(true), .noChange)
        XCTAssertEqual(eq.setDirect(true), .noChange)
        XCTAssertEqual(eq.setDirect(false), .noChange)
    }

    func test_editsInDirectAreKeptButNotApplied() {
        let eq = EQController()
        eq.setDirect(true)
        XCTAssertEqual(eq.apply(curve), .noChange)
        XCTAssertFalse(eq.isEnabled)
        XCTAssertEqual(eq.bands, curve)
    }

    func test_choosingParametricProfileLeavesDirect() {
        let eq = EQController()
        eq.setDirect(true)
        let preset = ParametricEQPreset(name: "HD 650", preamp: -6,
                                        bands: [ParametricBand(type: .peak, frequency: 100, gain: 4, q: 1)])
        XCTAssertEqual(eq.setParametric(preset), .becameEnabled)
        XCTAssertFalse(eq.isDirect)
        XCTAssertTrue(eq.isEnabled)
    }

    func test_modeAndCurvePersistAcrossRelaunch() {
        let store = InMemoryKeyValueStore()
        let eq = EQController(store: store)
        eq.apply(curve)
        eq.setDirect(true)
        eq.flushPendingWrites()

        let relaunched = EQController(store: store)
        XCTAssertTrue(relaunched.isDirect)
        XCTAssertEqual(relaunched.bands, curve)
        XCTAssertFalse(relaunched.isEnabled)
    }

    func test_settingsWrittenBeforeDirectModeStillLoad() throws {
        struct OldState: Codable { let bands: [Float]; let parametric: ParametricEQPreset? }
        let store = InMemoryKeyValueStore()
        try store.save(SchemaStore.encode([OldState(bands: curve, parametric: nil)],
                                          schemaVersion: EQController.schemaVersion))
        let eq = EQController(store: store)
        XCTAssertEqual(eq.bands, curve)
        XCTAssertFalse(eq.isDirect)
        XCTAssertTrue(eq.isEnabled)
    }

    // MARK: - PlayerManager transitions

    func test_playerModeSwitchPreservesQueueAndCurve() {
        let player = PlayerManager(urlSession: MockURLSession())
        player.applyEQPreset(curve)
        player.addToQueue(Track(id: "q1", title: "Next", artist: "A"))

        player.setAudioMode(direct: true)
        XCTAssertFalse(player.eq.isEnabled)
        player.setAudioMode(direct: false)

        XCTAssertTrue(player.eq.isEnabled)
        XCTAssertEqual(player.eq.bands, curve)
        XCTAssertEqual(player.queue.map(\.id), ["q1"])
    }

    // MARK: - Headroom

    func test_flatOrCutOnlyCurveNeedsNoPreamp() {
        let f = PlayerManager.eqFrequencies
        XCTAssertEqual(EQHeadroom.preamp(frequencies: f, gains: Array(repeating: 0, count: 10)), 0)
        XCTAssertEqual(EQHeadroom.preamp(frequencies: f, gains: Array(repeating: -6, count: 10)), 0)
    }

    /// Reference values measured on macOS through the real AUNBandEQ:
    /// single +12 band 11.91 dB, all bands +12 → 14.14 dB. The model must
    /// cover the measurement (never under-estimate) within ~0.3 dB.
    func test_preampCoversMeasuredPeaks() {
        let f = PlayerManager.eqFrequencies
        var single = [Float](repeating: 0, count: 10); single[5] = 12
        let one = EQHeadroom.peakGain(frequencies: f, gains: single)
        XCTAssertGreaterThanOrEqual(one, 11.91)
        XCTAssertLessThan(one, 12.2)

        let all = EQHeadroom.peakGain(frequencies: f, gains: Array(repeating: 12, count: 10))
        XCTAssertGreaterThanOrEqual(all, 14.14, "overlapping bands sum above the largest single gain")
        XCTAssertLessThan(all, 14.5)
    }

    // MARK: - Playback failures

    func test_corruptLocalFileSurfacesClearError() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_\(UUID().uuidString).flac")
        try Data((0..<4096).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let player = PlayerManager(urlSession: MockURLSession())
        player.play(Track(id: "corrupt", title: "Dañado", artist: "A", localFileURL: url))

        for _ in 0..<50 where player.playerError == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(player.playerError, .streamFailed(PlayerManager.localPlaybackFailureMessage))
        XCTAssertFalse(player.isPlaying)
    }
}
