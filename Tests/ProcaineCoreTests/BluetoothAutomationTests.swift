import XCTest
@testable import ProcaineCore

private final class Controller: BluetoothPowerControlling {
    var power: BluetoothPower = .on
    var requests: [BluetoothPower] = []
    var reads = 0
    func readPower() -> BluetoothPower { reads += 1; return power }
    func requestPower(_ state: BluetoothPower) { requests.append(state) }
}

private final class Clock {
    var callbacks: [(Double, () -> Void)] = []
    func schedule(_ delay: Double, _ callback: @escaping () -> Void) { callbacks.append((delay, callback)) }
    func run() {
        let work = callbacks
        callbacks.removeAll()
        work.forEach { $0.1() }
    }
}

final class BluetoothAutomationTests: XCTestCase {
    private func make(_ power: BluetoothPower = .on, paused: Bool = false)
        -> (BluetoothAutomation, Controller, Clock) {
        let controller = Controller()
        controller.power = power
        let clock = Clock()
        return (BluetoothAutomation(controller: controller, paused: paused, schedule: clock.schedule), controller, clock)
    }

    func testLaunchOnlyReadsCurrentState() {
        for state in [BluetoothPower.on, .off, .unknown] {
            let (app, controller, _) = make(state)
            app.refresh()
            XCTAssertEqual(app.reportedPower, state)
            XCTAssertTrue(controller.requests.isEmpty)
        }
    }

    func testOnlyAnOwnedSleepTransitionIsRestored() {
        let (app, controller, clock) = make()
        app.sleep()
        XCTAssertEqual(controller.requests, [.off])
        controller.power = .off
        clock.run()
        XCTAssertEqual(app.transition, .confirmed(.off))
        app.wake()
        XCTAssertEqual(controller.requests, [.off, .on])
        controller.power = .on
        clock.run()
        XCTAssertEqual(app.transition, .confirmed(.on))
        XCTAssertFalse(app.canRestore)
    }

    func testManualOffAndUnknownAreNeverOverridden() {
        for state in [BluetoothPower.off, .unknown] {
            let (app, controller, clock) = make(state)
            app.sleep()
            app.wake()
            clock.run()
            XCTAssertTrue(controller.requests.isEmpty)
        }
    }

    func testDuplicateNotificationsDoNotRepeatRequests() {
        let (app, controller, _) = make()
        app.sleep(); app.sleep()
        controller.power = .off
        app.wake(); app.wake()
        XCTAssertEqual(controller.requests, [.off, .on])
    }

    func testWakeWithoutOwnedSleepDoesNotToggle() {
        let (app, controller, _) = make(.off)
        app.wake()
        XCTAssertTrue(controller.requests.isEmpty)
    }

    func testAlreadyRestoredRadioDoesNotReceiveAnotherOnRequest() {
        let (app, controller, _) = make()
        app.sleep()
        app.wake()
        XCTAssertEqual(controller.requests, [.off])
    }

    func testFailedSleepRequestDoesNotForceAnotherPowerChange() {
        let (app, controller, clock) = make()
        app.sleep()
        clock.run()
        XCTAssertEqual(app.transition, .unconfirmed(.off))
        app.wake()
        XCTAssertEqual(controller.requests, [.off])
    }

    func testFailedWakeOffersOnlyExplicitManualRetry() {
        let (app, controller, clock) = make()
        app.sleep()
        controller.power = .off
        app.wake()
        clock.run()
        XCTAssertEqual(app.transition, .unconfirmed(.on))
        XCTAssertTrue(app.canRestore)
        XCTAssertEqual(controller.requests, [.off, .on])
        app.restoreManually()
        XCTAssertEqual(controller.requests, [.off, .on, .on])
        controller.power = .on
        clock.run()
        XCTAssertFalse(app.canRestore)
    }

    func testUnavailableWakeDoesNotSpeculativelyToggle() {
        let (app, controller, clock) = make()
        app.sleep()
        controller.power = .unknown
        app.wake()
        clock.run()
        app.restoreManually()
        XCTAssertEqual(controller.requests, [.off])
        XCTAssertEqual(app.transition, .unconfirmed(.on))
    }

    func testStaleSamplesAreIgnoredAfterWake() {
        let (app, controller, clock) = make()
        app.sleep()
        let stale = clock.callbacks
        clock.callbacks.removeAll()
        controller.power = .off
        app.wake()
        let reads = controller.reads
        stale.forEach { $0.1() }
        XCTAssertEqual(controller.reads, reads)
        XCTAssertEqual(app.transition, .pending(.on))
    }

    func testRapidResleepRetainsOwnershipButCancelsOldSamples() {
        let (app, controller, clock) = make()
        app.sleep()
        controller.power = .off
        app.wake()
        app.sleep()
        let reads = controller.reads
        clock.run()
        XCTAssertEqual(controller.reads, reads)
        XCTAssertEqual(controller.requests, [.off, .on])
        app.wake()
        XCTAssertEqual(controller.requests, [.off, .on, .on])
    }

    func testPauseInvalidatesWorkAndResumeDoesNotToggle() {
        let (app, controller, clock) = make()
        app.sleep()
        app.setPaused(true)
        controller.power = .off
        let reads = controller.reads
        clock.run()
        XCTAssertEqual(controller.reads, reads)
        app.wake()
        app.setPaused(false)
        XCTAssertEqual(controller.requests, [.off])
        XCTAssertFalse(app.canRestore)
    }

    func testPausedSleepCycleDoesNotChangePower() {
        let (app, controller, clock) = make(paused: true)
        app.sleep(); app.wake(); clock.run()
        XCTAssertTrue(controller.requests.isEmpty)
    }

    func testDisabledSleepActionDoesNotReadBluetoothOnSleep() {
        let (app, controller, _) = make(paused: true)
        app.sleep()
        app.wake()
        XCTAssertEqual(controller.reads, 0)
    }

    func testLateSuccessClearsWarningWithoutRetry() {
        let (app, controller, clock) = make()
        app.sleep()
        controller.power = .off
        app.wake()
        clock.run()
        controller.power = .on
        app.refresh()
        XCTAssertEqual(app.transition, .confirmed(.on))
        XCTAssertFalse(app.canRestore)
        XCTAssertEqual(controller.requests, [.off, .on])
    }

    func testManualOffAfterSuccessfulWakeStaysOffNextCycle() {
        let (app, controller, clock) = make()
        app.sleep()
        controller.power = .off
        app.wake()
        controller.power = .on
        clock.run()
        controller.power = .off
        app.sleep(); app.wake()
        XCTAssertEqual(controller.requests, [.off, .on])
    }

    func testVerificationIsBoundedAndNeverRetries() {
        let (app, controller, clock) = make()
        app.sleep()
        XCTAssertEqual(clock.callbacks.map { $0.0 }, [0, 0.25, 1, 3])
        clock.run()
        XCTAssertTrue(clock.callbacks.isEmpty)
        XCTAssertEqual(controller.requests, [.off])
    }
}
