import XCTest
@testable import ProcaineCore

private final class Radio: BluetoothPowerControlling {
    var state: BluetoothPower = .on
    var requests: [BluetoothPower] = []
    var reads = 0
    func readPower() -> BluetoothPower { reads += 1; return state }
    func requestPower(_ power: BluetoothPower) { requests.append(power); state = power }
}

private final class Logi: AppServiceControlling {
    var stops = 0
    var restores = 0
    func probe(_ completion: @escaping (AppServicePresence) -> Void) { completion(.running) }
    func stop(_ completion: @escaping (Bool) -> Void) { stops += 1; completion(true) }
    func restore(_ completion: @escaping (Bool) -> Void) { restores += 1; completion(true) }
}

final class SleepActionIndependenceTests: XCTestCase {
    func testAllFourToggleCombinationsRemainIndependent() {
        for radioEnabled in [false, true] {
            for logiEnabled in [false, true] {
                let radio = Radio()
                let logi = Logi()
                let bluetooth = BluetoothAutomation(controller: radio, paused: !radioEnabled, schedule: { _, _ in })
                let app = AppSleepAutomation(service: logi, saveOwnership: { _ in true })
                app.setPaused(!logiEnabled)
                bluetooth.sleep(); app.sleep()
                bluetooth.wake(); app.wake()
                XCTAssertEqual(radio.requests, radioEnabled ? [.off, .on] : [])
                XCTAssertEqual(logi.stops, logiEnabled ? 1 : 0)
                XCTAssertEqual(logi.restores, logiEnabled ? 1 : 0)
                if !radioEnabled { XCTAssertEqual(radio.reads, 0) }
            }
        }
    }

    func testAppServiceFailureNeverFallsBackToRadioPowerControl() {
        let radio = Radio()
        let bluetooth = BluetoothAutomation(controller: radio, paused: true, schedule: { _, _ in })
        final class FailingService: AppServiceControlling {
            func probe(_ completion: @escaping (AppServicePresence) -> Void) { completion(.running) }
            func stop(_ completion: @escaping (Bool) -> Void) { completion(false) }
            func restore(_ completion: @escaping (Bool) -> Void) { completion(false) }
        }
        let app = AppSleepAutomation(service: FailingService(), saveOwnership: { _ in true })
        app.setPaused(false)
        bluetooth.sleep(); app.sleep()
        bluetooth.wake(); app.wake()
        XCTAssertEqual(app.phase, .restoreFailed)
        XCTAssertTrue(radio.requests.isEmpty)
        XCTAssertEqual(radio.reads, 0)
    }
}
