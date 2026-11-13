#if os(macOS)
import XCTest
@testable import Ailen

@MainActor
final class MacAudioOutputMonitorTests: XCTestCase {
    private final class FakeReader: AudioDeviceReading {
        var current: AudioOutputSnapshot
        var list: [MacOutputDevice]
        init(_ current: AudioOutputSnapshot, _ list: [MacOutputDevice] = []) {
            self.current = current
            self.list = list
        }
        func snapshot() -> AudioOutputSnapshot { current }
        func devices() -> [MacOutputDevice] { list }
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) {}
    }

    func test_usbDAC_isReportedWithItsRealRate() {
        let dac = AudioOutputSnapshot(deviceUID: "dac", deviceName: "Topping E30", kind: .usb, sampleRate: 96_000)
        let monitor = AudioOutputMonitor(reader: FakeReader(dac))
        XCTAssertTrue(monitor.snapshot.isUSBDAC)
        XCTAssertEqual(monitor.snapshot.displayText, "Salida: USB · Topping E30 · 96 kHz")
    }

    func test_bluetoothAndBuiltIn_areNeverAUSBDAC() {
        for kind in [AudioOutputKind.bluetooth, .builtIn, .hdmi, .airPlay] {
            let s = AudioOutputSnapshot(deviceName: "X", kind: kind, sampleRate: 48_000)
            XCTAssertFalse(s.isUSBDAC, "\(kind) must not show as DAC USB")
        }
    }

    func test_noOutput_andUnknownRate_sayNoDisponible() {
        XCTAssertEqual(AudioOutputSnapshot.none.displayText, "Salida: No disponible")
        let s = AudioOutputSnapshot(deviceName: "Altavoces", kind: .builtIn, sampleRate: nil)
        XCTAssertEqual(s.displayText, "Salida: Integrada · Altavoces · No disponible")
    }

    func test_refresh_picksUpDeviceSwitchAndList() {
        let reader = FakeReader(AudioOutputSnapshot(deviceUID: "spk", deviceName: "Altavoces", kind: .builtIn, sampleRate: 48_000))
        let monitor = AudioOutputMonitor(reader: reader)
        reader.current = AudioOutputSnapshot(deviceUID: "dac", deviceName: "DAC", kind: .usb, sampleRate: 44_100)
        reader.list = [MacOutputDevice(uid: "dac", name: "DAC", kind: .usb)]
        monitor.refresh()
        XCTAssertEqual(monitor.snapshot.deviceUID, "dac")
        XCTAssertEqual(monitor.snapshot.sampleRate, 44_100)
        XCTAssertEqual(monitor.devices.map(\.uid), ["dac"])
    }
}
#endif
