import Foundation

enum BluetoothPower: Equatable {
    case on, off, unknown
}

protocol BluetoothPowerControlling {
    func readPower() -> BluetoothPower
    func requestPower(_ state: BluetoothPower)
}

/// All events and scheduled callbacks must run on the main thread.
/// Observed power describes macOS's report, not accessory connection readiness.
final class BluetoothAutomation {
    enum Transition: Equatable {
        case idle
        case pending(BluetoothPower)
        case confirmed(BluetoothPower)
        case unconfirmed(BluetoothPower)
    }

    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private let controller: BluetoothPowerControlling
    private let schedule: Schedule
    private var generation = 0
    private var restoreOwed = false
    private(set) var isPaused: Bool
    private(set) var isAsleep = false
    private(set) var reportedPower: BluetoothPower = .unknown
    private(set) var transition: Transition = .idle
    var onChange: (() -> Void)?
    var onSample: ((_ target: BluetoothPower, _ observed: BluetoothPower, _ elapsed: TimeInterval) -> Void)?

    init(controller: BluetoothPowerControlling, paused: Bool = false,
         schedule: @escaping Schedule = { delay, callback in
             DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: callback)
         }) {
        self.controller = controller
        self.isPaused = paused
        self.schedule = schedule
    }

    var canRestore: Bool {
        !isPaused && !isAsleep && restoreOwed && transition == .unconfirmed(.on)
    }

    func refresh() {
        reportedPower = controller.readPower()
        // A late successful restore should clear an earlier warning without another request.
        if !isAsleep && restoreOwed && reportedPower == .on {
            restoreOwed = false
            generation += 1
            transition = .confirmed(.on)
        }
        onChange?()
    }

    func sleep() {
        guard !isAsleep else { return }
        isAsleep = true
        invalidate()
        guard !isPaused else { onChange?(); return }
        reportedPower = controller.readPower()
        switch reportedPower {
        case .on:
            restoreOwed = true
            request(.off)
        case .off:
            // Keep an outstanding restore across a rapid re-sleep during wake restoration.
            onChange?()
        case .unknown:
            restoreOwed = false
            onChange?()
        }
    }

    func wake() {
        guard isAsleep else { return }
        isAsleep = false
        invalidate()
        guard !isPaused else { onChange?(); return }
        guard restoreOwed else { refresh(); return }
        reportedPower = controller.readPower()
        if reportedPower == .on {
            restoreOwed = false
            transition = .confirmed(.on)
            onChange?()
        } else if reportedPower == .off {
            request(.on)
        } else {
            transition = .unconfirmed(.on)
            onChange?()
        }
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        invalidate()
        restoreOwed = false
        onChange?()
    }

    func restoreManually() {
        guard canRestore else { return }
        reportedPower = controller.readPower()
        guard reportedPower == .off else { refresh(); return }
        request(.on)
    }

    private func invalidate() {
        generation += 1
        transition = .idle
    }

    private func request(_ target: BluetoothPower) {
        generation += 1
        let token = generation
        let started = ProcessInfo.processInfo.systemUptime
        transition = .pending(target)
        controller.requestPower(target)
        onChange?()
        for delay in [0.0, 0.25, 1.0, 3.0] {
            schedule(delay) { [weak self] in
                guard let self = self, token == self.generation else { return }
                self.reportedPower = self.controller.readPower()
                self.onSample?(target, self.reportedPower, ProcessInfo.processInfo.systemUptime - started)
                if self.reportedPower == target {
                    self.transition = .confirmed(target)
                    if target == .on { self.restoreOwed = false }
                } else if delay == 3.0 {
                    self.transition = .unconfirmed(target)
                }
                self.onChange?()
            }
        }
    }
}
