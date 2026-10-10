import Foundation

enum AppServicePresence: Equatable { case running, notRunning, unavailable }

protocol AppServiceControlling {
    func probe(_ completion: @escaping (AppServicePresence) -> Void)
    func stop(_ completion: @escaping (Bool) -> Void)
    func restore(_ completion: @escaping (Bool) -> Void)
}

/// Serializes one supported app's lifecycle. Completion handlers run on the main thread.
/// A saved ownership marker permits recovery after Procaine is relaunched following a crash.
final class AppSleepAutomation {
    enum Phase: Equatable { case idle, checking, stopping, stopped, restoring, stopFailed, restoreFailed, unavailable }
    private let service: AppServiceControlling
    private let saveOwnership: (Bool) -> Bool
    private var busy = false
    private var attemptedStop = false
    private var attemptedRestore = false
    private(set) var isAsleep = false
    private(set) var isPaused = true
    private(set) var ownsStop: Bool
    private(set) var phase: Phase = .idle
    var onChange: (() -> Void)?

    init(service: AppServiceControlling, ownsStop: Bool = false, saveOwnership: @escaping (Bool) -> Bool) {
        self.service = service
        self.ownsStop = ownsStop
        self.saveOwnership = saveOwnership
    }

    var canRestore: Bool { ownsStop && !isAsleep && !busy }
    var isBusy: Bool { busy }

    func startRecovery() { reconcile() }

    func sleep() {
        guard !isAsleep else { return }
        isAsleep = true
        attemptedStop = false
        reconcile()
    }

    func wake() {
        guard isAsleep else { return }
        isAsleep = false
        attemptedRestore = false
        reconcile()
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        // Pausing never stops anything; awake recovery remains allowed.
        reconcile()
    }

    func restoreManually() {
        guard canRestore else { return }
        attemptedRestore = false
        reconcile()
    }

    private func reconcile() {
        guard !busy else { onChange?(); return }
        if !isAsleep && ownsStop && !attemptedRestore {
            busy = true
            attemptedRestore = true
            phase = .restoring
            onChange?()
            service.restore { [weak self] succeeded in
                guard let self = self else { return }
                self.busy = false
                if succeeded {
                    let cleared = self.saveOwnership(false)
                    self.ownsStop = !cleared
                    self.phase = cleared ? .idle : .restoreFailed
                } else {
                    self.phase = .restoreFailed
                }
                self.onChange?()
                // A new sleep may have arrived while restoration was in flight.
                if succeeded { self.reconcile() }
            }
        } else if isAsleep && !isPaused && !ownsStop && !attemptedStop {
            busy = true
            attemptedStop = true
            phase = .checking
            onChange?()
            service.probe { [weak self] presence in
                guard let self = self else { return }
                self.busy = false
                guard self.isAsleep && !self.isPaused else {
                    self.phase = .idle
                    self.reconcile()
                    return
                }
                switch presence {
                case .running:
                    // Persist before the stop, so a crash cannot lose the recovery obligation.
                    guard self.saveOwnership(true) else {
                        self.phase = .unavailable
                        self.onChange?()
                        return
                    }
                    self.ownsStop = true
                    self.attemptedRestore = false
                    self.busy = true
                    self.phase = .stopping
                    self.onChange?()
                    self.service.stop { [weak self] succeeded in
                        guard let self = self else { return }
                        self.busy = false
                        self.phase = succeeded ? .stopped : .stopFailed
                        self.onChange?()
                        // If wake happened mid-stop, restore immediately after its completion.
                        self.reconcile()
                    }
                case .notRunning: self.phase = .idle; self.onChange?()
                case .unavailable: self.phase = .unavailable; self.onChange?()
                }
            }
        } else {
            onChange?()
        }
    }
}
