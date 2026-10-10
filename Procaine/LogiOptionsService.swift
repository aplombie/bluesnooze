import Foundation

final class LogiRecoveryStore {
    private var marker: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Procaine/logi-service-recovery.json")
    }

    var ownsStop: Bool { FileManager.default.fileExists(atPath: marker.path) }

    func save(_ owned: Bool) -> Bool {
        do {
            if owned {
                try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("{\"service\":\"com.logi.cp-dev-mgr\",\"format\":1}".utf8).write(to: marker, options: .atomic)
            } else if ownsStop {
                try FileManager.default.removeItem(at: marker)
            }
            return true
        } catch { return false }
    }
}

/// Explicitly allowlisted integration. Never touches the updater, other Logi services,
/// system launchd domain, login preferences, pairings, or Bluetooth radio power.
final class LogiOptionsService: AppServiceControlling {
    static let label = "com.logi.cp-dev-mgr"
    static let plist = "/Library/LaunchAgents/com.logi.optionsplus.plist"
    private var pendingUnload = false
    private let queue = DispatchQueue(label: "io.github.aplombie.procaine.logi-service")
    private var target: String { "gui/\(getuid())/\(Self.label)" }
    private var domain: String { "gui/\(getuid())" }

    var isInstalled: Bool {
        guard let data = FileManager.default.contents(atPath: Self.plist),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return dictionary["Label"] as? String == Self.label
    }

    func probe(_ completion: @escaping (AppServicePresence) -> Void) {
        guard isInstalled else { completion(.unavailable); return }
        run(["print", target]) { code, output in
            if code == 0 {
                let running = output.split(whereSeparator: \.isNewline).contains {
                    $0.trimmingCharacters(in: .whitespaces) == "state = running"
                }
                completion(running ? .running : .notRunning)
            } else {
                completion(code == 113 ? .notRunning : .unavailable)
            }
        }
    }

    func stop(_ completion: @escaping (Bool) -> Void) {
        guard isInstalled else { completion(false); return }
        run(["bootout", target]) { [weak self] code, _ in
            guard code == 0, let self = self else { completion(false); return }
            self.pendingUnload = true
            self.confirmUnloaded(attempt: 0, completion: completion)
        }
    }

    func restore(_ completion: @escaping (Bool) -> Void) {
        guard isInstalled else { completion(false); return }
        if pendingUnload {
            confirmUnloaded(attempt: 0) { [weak self] unloaded in
                guard unloaded, let self = self else { completion(false); return }
                self.restore(completion)
            }
            return
        }
        run(["print", target]) { [weak self] code, output in
            guard let self = self else { completion(false); return }
            if code == 0 {
                if output.split(whereSeparator: \.isNewline).contains(where: {
                    $0.trimmingCharacters(in: .whitespaces) == "state = running"
                }) {
                    completion(true)
                    return
                }
                // Kickstart without -k does not kill an already running service.
                self.run(["kickstart", self.target]) { [weak self] result, _ in
                    guard result == 0, let self = self else { completion(false); return }
                    self.confirmRunning(attempt: 0, completion: completion)
                }
            } else if code == 113 {
                self.run(["bootstrap", self.domain, Self.plist]) { [weak self] result, _ in
                    guard result == 0, let self = self else { completion(false); return }
                    self.confirmRunning(attempt: 0, completion: completion)
                }
            } else { completion(false) }
        }
    }

    // bootout can return before launchd has removed the job. Never kickstart or
    // bootstrap a job that is still being unloaded by our own stop request.
    private func confirmUnloaded(attempt: Int, completion: @escaping (Bool) -> Void) {
        run(["print", target]) { [weak self] code, _ in
            guard let self = self else { completion(false); return }
            if code == 113 {
                self.pendingUnload = false
                completion(true)
            } else if code != 0 || attempt == 5 {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + [0.25, 0.75, 2.0, 3.0, 4.0][attempt]) {
                    self.confirmUnloaded(attempt: attempt + 1, completion: completion)
                }
            }
        }
    }

    private func confirmRunning(attempt: Int, completion: @escaping (Bool) -> Void) {
        probe { [weak self] presence in
            guard let self = self else { completion(false); return }
            if presence == .running { completion(true) }
            else if attempt == 3 { completion(false) }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + [0.25, 0.75, 2.0][attempt]) { [weak self] in
                    guard let self = self else { completion(false); return }
                    self.confirmRunning(attempt: attempt + 1, completion: completion)
                }
            }
        }
    }

    private final class OutputBuffer {
        private let lock = NSLock()
        private var bytes = Data()
        func append(_ data: Data) {
            lock.lock()
            bytes.append(data.prefix(max(0, 65_536 - bytes.count)))
            lock.unlock()
        }
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private func run(_ arguments: [String], completion: @escaping (Int32, String) -> Void) {
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = arguments
            let capture = arguments.first == "print"
            let pipe = Pipe()
            let output = OutputBuffer()
            process.standardOutput = capture ? pipe : FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            let reader = DispatchGroup()
            process.terminationHandler = { _ in finished.signal() }
            let result: Int32
            do {
                try process.run()
                if capture {
                    reader.enter()
                    DispatchQueue.global(qos: .utility).async {
                        defer { reader.leave() }
                        while true {
                            let data = pipe.fileHandleForReading.availableData
                            guard !data.isEmpty else { return }
                            output.append(data)
                        }
                    }
                }
                if finished.wait(timeout: .now() + 5) == .timedOut {
                    // Terminate only our launchctl client, never a guessed target process.
                    process.terminate()
                    if finished.wait(timeout: .now() + 0.25) == .timedOut {
                        kill(process.processIdentifier, SIGKILL)
                    }
                    result = -1
                } else {
                    result = process.terminationStatus
                }
                _ = reader.wait(timeout: .now() + 1)
            } catch { result = -1 }
            // Raw launchctl output stays in memory and is never displayed or logged.
            let text = output.text
            DispatchQueue.main.async { completion(result, text) }
        }
    }
}
