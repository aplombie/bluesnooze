import XCTest
@testable import ProcaineCore

private final class Service: AppServiceControlling {
    var probes: [(AppServicePresence) -> Void] = []
    var stops: [(Bool) -> Void] = []
    var restores: [(Bool) -> Void] = []
    func probe(_ completion: @escaping (AppServicePresence) -> Void) { probes.append(completion) }
    func stop(_ completion: @escaping (Bool) -> Void) { stops.append(completion) }
    func restore(_ completion: @escaping (Bool) -> Void) { restores.append(completion) }
}

final class AppSleepAutomationTests: XCTestCase {
    func testDisabledActionDoesNothingAtLaunchOrSleep() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.startRecovery(); app.sleep(); app.wake()
        XCTAssertTrue(service.probes.isEmpty)
        XCTAssertTrue(service.stops.isEmpty)
        XCTAssertTrue(service.restores.isEmpty)
    }

    func testOwnershipIsPersistedBeforeStopAndClearedOnlyAfterRestore() {
        let service = Service()
        var marker = false
        let app = AppSleepAutomation(service: service, saveOwnership: { marker = $0; return true })
        app.setPaused(false)
        app.sleep()
        service.probes[0](.running)
        XCTAssertTrue(marker)
        XCTAssertEqual(service.stops.count, 1)
        service.stops[0](true)
        XCTAssertEqual(app.phase, .stopped)
        app.wake()
        XCTAssertTrue(marker)
        service.restores[0](true)
        XCTAssertFalse(marker)
        XCTAssertFalse(app.ownsStop)
    }

    func testWakeDuringProbePreventsLateStop() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.setPaused(false); app.sleep(); app.wake()
        service.probes[0](.running)
        XCTAssertTrue(service.stops.isEmpty)
    }

    func testWakeDuringStopWaitsThenRestores() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.setPaused(false); app.sleep()
        service.probes[0](.running)
        app.wake()
        XCTAssertTrue(service.restores.isEmpty)
        service.stops[0](true)
        XCTAssertEqual(service.restores.count, 1)
        service.restores[0](true)
        XCTAssertFalse(app.ownsStop)
    }

    func testUnavailableOrInactiveServiceIsNotStoppedOrRestored() {
        for presence in [AppServicePresence.notRunning, .unavailable] {
            let service = Service()
            let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
            app.setPaused(false); app.sleep()
            service.probes[0](presence)
            app.wake()
            XCTAssertTrue(service.stops.isEmpty)
            XCTAssertTrue(service.restores.isEmpty)
        }
    }

    func testFailedOwnershipWritePreventsStop() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in false })
        app.setPaused(false); app.sleep()
        service.probes[0](.running)
        XCTAssertTrue(service.stops.isEmpty)
        XCTAssertFalse(app.ownsStop)
        XCTAssertEqual(app.phase, .unavailable)
    }

    func testFailedRestoreRetainsMarkerAndOffersManualRecoveryWithoutLoop() {
        let service = Service()
        let app = AppSleepAutomation(service: service, ownsStop: true, saveOwnership: { _ in true })
        app.startRecovery()
        service.restores[0](false)
        XCTAssertTrue(app.ownsStop)
        XCTAssertTrue(app.canRestore)
        XCTAssertEqual(app.phase, .restoreFailed)
        XCTAssertEqual(service.restores.count, 1)
        app.restoreManually()
        XCTAssertEqual(service.restores.count, 2)
        service.restores[1](true)
        XCTAssertFalse(app.ownsStop)
    }

    func testCrashMarkerRecoversEvenWithActionDisabled() {
        let service = Service()
        let app = AppSleepAutomation(service: service, ownsStop: true, saveOwnership: { _ in true })
        app.startRecovery()
        XCTAssertTrue(app.isPaused)
        XCTAssertEqual(service.restores.count, 1)
        service.restores[0](true)
        XCTAssertFalse(app.ownsStop)
    }

    func testPauseDuringProbeCancelsStop() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.setPaused(false); app.sleep(); app.setPaused(true)
        service.probes[0](.running)
        XCTAssertTrue(service.stops.isEmpty)
    }

    func testDuplicateEventsDoNotRepeatServiceCommands() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.setPaused(false); app.sleep(); app.sleep()
        XCTAssertEqual(service.probes.count, 1)
        service.probes[0](.running)
        service.stops[0](true)
        app.wake(); app.wake()
        XCTAssertEqual(service.restores.count, 1)
    }

    func testFailedStopStillRetainsRecoveryObligation() {
        let service = Service()
        let app = AppSleepAutomation(service: service, saveOwnership: { _ in true })
        app.setPaused(false); app.sleep()
        service.probes[0](.running)
        service.stops[0](false)
        XCTAssertEqual(app.phase, .stopFailed)
        app.wake()
        XCTAssertEqual(service.restores.count, 1)
    }

    func testRapidResleepDuringRestoreIsSerialized() {
        let service = Service()
        let app = AppSleepAutomation(service: service, ownsStop: true, saveOwnership: { _ in true })
        app.setPaused(false)
        app.startRecovery(); app.sleep()
        XCTAssertTrue(service.probes.isEmpty)
        service.restores[0](true)
        XCTAssertEqual(service.probes.count, 1)
        service.probes[0](.running)
        XCTAssertEqual(service.stops.count, 1)
    }
}
