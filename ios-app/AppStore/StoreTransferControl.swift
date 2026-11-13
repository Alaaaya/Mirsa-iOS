import Foundation
import Combine
import Network

/// One download run. Owns its own pause/discard state, so a finished run can never affect the next one.
final class StoreTransferRun: @unchecked Sendable {
    let id = UUID()
    private let lock = NSLock()
    private var paused = false
    private var discard = false
    private var cancelAttempt: (() -> Void)?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var earlyCancel = Set<UUID>()

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return paused }
    /// True only after the user explicitly pressed Cancel for THIS run.
    var discardRequested: Bool { lock.lock(); defer { lock.unlock() }; return discard }

    /// Stops the in-flight request (if any) but keeps the partial file.
    func pause() {
        lock.lock(); paused = true; let cancel = cancelAttempt; lock.unlock()
        cancel?()
    }

    func resume() {
        lock.lock(); paused = false
        let all = waiters; waiters = [:]; lock.unlock()
        all.values.forEach { $0.resume() }
    }

    func cancelNow() { pause() }

    func requestDiscard() {
        lock.lock(); discard = true; paused = false
        let cancel = cancelAttempt
        let all = waiters; waiters = [:]; lock.unlock()
        cancel?()
        all.values.forEach { $0.resume() }
    }

    /// Registers the single in-flight request. Returns false if the run is paused or discarded.
    func register(_ cancel: @escaping () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if paused || discard { return false }
        cancelAttempt = cancel
        return true
    }

    func unregister() { lock.lock(); cancelAttempt = nil; lock.unlock() }

    /// Returns when not paused. A cancelled task wakes immediately.
    func waitWhilePaused() async {
        let id = UUID()
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                lock.lock()
                if earlyCancel.remove(id) != nil || !paused || discard { lock.unlock(); c.resume() }
                else { waiters[id] = c; lock.unlock() }
            }
        }, onCancel: {
            lock.lock()
            let c = waiters.removeValue(forKey: id)
            if c == nil { earlyCancel.insert(id) }
            lock.unlock()
            c?.resume()
        })
        lock.lock(); earlyCancel.remove(id); lock.unlock()
    }
}

/// Observable status of the one visible App Store transfer, for the UI.
final class StoreTransferControl: ObservableObject, @unchecked Sendable {
    static let shared = StoreTransferControl()
    enum Phase: Equatable { case idle, running, paused, waitingForNetwork }
    @Published private(set) var phase = Phase.idle
    @Published private(set) var received: Int64 = 0
    @Published private(set) var expected: Int64 = 0
    private let lock = NSLock()
    private var current: StoreTransferRun?
    private var generation: UInt64 = 0
    private let enqueue: (@escaping () -> Void) -> Void

    init(enqueue: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.enqueue = enqueue
    }

    func begin() -> StoreTransferRun {
        let run = StoreTransferRun()
        lock.lock(); generation &+= 1; current = run; lock.unlock()
        publish(run, .running, 0, 0)
        return run
    }

    func end(_ run: StoreTransferRun) {
        lock.lock()
        guard current === run else { lock.unlock(); return }
        let endedGeneration = generation
        current = nil; lock.unlock()
        run.resume()
        enqueue {
            guard self.isEndedGeneration(endedGeneration) else { return }
            self.phase = .idle; self.received = 0; self.expected = 0
        }
    }

    private var run: StoreTransferRun? { lock.lock(); defer { lock.unlock() }; return current }

    func pause() { guard let r = run else { return }; setPhase(r, .paused); r.pause() }
    func resume() { guard let r = run else { return }; setPhase(r, .running); r.resume() }
    /// Explicit user Cancel: the partial of this run is deleted.
    func discardCurrent() { run?.requestDiscard() }
    /// Stops the attempt without deleting the partial (used when the screen goes away).
    func cancelCurrent() { run?.cancelNow() }

    func setPhase(_ run: StoreTransferRun, _ p: Phase) {
        enqueue { if self.isCurrent(run) { self.phase = p } }
    }
    func progress(_ run: StoreTransferRun, _ r: Int64, _ e: Int64) {
        enqueue { if self.isCurrent(run) { self.received = r; self.expected = e } }
    }
    private func publish(_ run: StoreTransferRun, _ p: Phase, _ r: Int64, _ e: Int64) {
        enqueue { if self.isCurrent(run) { self.phase = p; self.received = r; self.expected = e } }
    }
    private func isEndedGeneration(_ value: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return current == nil && generation == value
    }
    private func isCurrent(_ run: StoreTransferRun) -> Bool { lock.lock(); defer { lock.unlock() }; return current === run }
}

/// Waits (cancellation-aware, no polling) until the device has a usable network path.
enum StoreNetworkWait {
    enum Result: Equatable { case alreadyOnline, becameOnline, timedOut }

    static func untilOnline(timeout: TimeInterval = 600) async -> Result {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "mirsa.store.netwait")
        let gate = Gate()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (c: CheckedContinuation<Result, Never>) in
                gate.install(c, monitor: monitor)
                var first = true
                monitor.pathUpdateHandler = { path in
                    let wasFirst = first; first = false
                    if path.status == .satisfied { gate.finish(wasFirst ? .alreadyOnline : .becameOnline) }
                }
                monitor.start(queue: queue)
                queue.asyncAfter(deadline: .now() + timeout) { gate.finish(.timedOut) }
            }
        }, onCancel: { gate.finish(.timedOut) })
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<Result, Never>?
        private var monitor: NWPathMonitor?
        private var result: Result?
        func install(_ c: CheckedContinuation<Result, Never>, monitor: NWPathMonitor) {
            lock.lock()
            if let result { lock.unlock(); monitor.cancel(); c.resume(returning: result); return }
            cont = c; self.monitor = monitor; lock.unlock()
        }
        func finish(_ r: Result) {
            lock.lock()
            if result != nil { lock.unlock(); return }
            result = r
            let c = cont; cont = nil; let m = monitor; monitor = nil
            lock.unlock()
            m?.cancel(); c?.resume(returning: r)
        }
    }
}
