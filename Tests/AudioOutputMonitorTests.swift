import AVFoundation
import XCTest
@testable import Ailen

private final class FakeSession: AudioSessionReading {
    var outputPorts: [AudioOutputPort] = []
    var sampleRate: Double = 48_000
}

@MainActor
final class AudioOutputMonitorTests: XCTestCase {
    private let usb = AudioOutputPort(name: "FiiO KA3", type: .usbAudio)
    private let airpods = AudioOutputPort(name: "AirPods Pro", type: .bluetoothA2DP)
    private let speaker = AudioOutputPort(name: "Altavoz", type: .builtInSpeaker)

    private func makeMonitor(_ ports: [AudioOutputPort], rate: Double = 48_000)
        -> (AudioOutputMonitor, FakeSession, NotificationCenter) {
        let session = FakeSession()
        session.outputPorts = ports
        session.sampleRate = rate
        let center = NotificationCenter()
        return (AudioOutputMonitor(session: session, center: center), session, center)
    }

    func testUSBDACAfterActivation() {
        let (monitor, _, _) = makeMonitor([usb], rate: 96_000)
        monitor.sessionDidActivate()
        XCTAssertTrue(monitor.snapshot.isUSBDAC)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: USB · FiiO KA3 · 96 kHz")
    }

    func testRateUnknownBeforeActivation() {
        let (monitor, _, _) = makeMonitor([usb], rate: 96_000)
        XCTAssertNil(monitor.snapshot.sampleRate)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: USB · FiiO KA3 · No disponible")
    }

    func testBluetoothIsNotUSBDAC() {
        let (monitor, _, _) = makeMonitor([airpods])
        monitor.sessionDidActivate()
        XCTAssertFalse(monitor.snapshot.isUSBDAC)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: Bluetooth · AirPods Pro · 48 kHz")
    }

    func testWiredHeadphonesAreNotUSBDAC() {
        let (monitor, _, _) = makeMonitor([AudioOutputPort(name: "Headphones", type: .headphones)])
        monitor.sessionDidActivate()
        XCTAssertFalse(monitor.snapshot.isUSBDAC)
    }

    func testNoOutputs() {
        let (monitor, _, _) = makeMonitor([])
        monitor.sessionDidActivate()
        XCTAssertNil(monitor.snapshot.primary)
        XCTAssertNil(monitor.snapshot.sampleRate)
        XCTAssertFalse(monitor.snapshot.isUSBDAC)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: No disponible")
    }

    func testRouteChangeNotificationRefreshes() {
        let (monitor, session, center) = makeMonitor([usb])
        monitor.sessionDidActivate()
        session.outputPorts = [speaker]
        session.sampleRate = 44_100
        center.post(name: AVAudioSession.routeChangeNotification, object: nil)
        XCTAssertFalse(monitor.snapshot.isUSBDAC)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: Altavoz · 44.1 kHz")
    }

    func testInterruptionAndResetClearRateUntilReactivated() {
        let (monitor, _, center) = makeMonitor([usb])
        monitor.sessionDidActivate()
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertNil(monitor.snapshot.sampleRate)

        center.post(name: .ariaAudioSessionActivated, object: nil)
        XCTAssertEqual(monitor.snapshot.sampleRate, 48_000)

        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        XCTAssertNil(monitor.snapshot.sampleRate)
        XCTAssertTrue(monitor.snapshot.isUSBDAC, "the port stays known; only the rate is invalidated")
    }
}
