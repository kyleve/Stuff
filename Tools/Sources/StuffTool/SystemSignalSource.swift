import Darwin
import Dispatch
import StuffToolCore
import Synchronization

/// Converts the terminal signals a command can receive into serialized events.
final class SystemSignalSource: @unchecked Sendable {
    private static let observedSignals: [CommandSignal] = [
        .hangup,
        .interrupt,
        .quit,
        .brokenPipe,
        .terminate,
    ]

    private struct State {
        var forcedTerminationArmed = false
        var stopped = false
    }

    private let handler: @Sendable (SignalForwardingReport) -> Void
    private let queue = DispatchQueue(label: "com.stuff.tool-signals")
    private let relay: CommandSignalRelay
    #if DEBUG
        private let terminationHandler: (@Sendable (CommandSignal) -> Void)?
    #endif
    private let watchdogDelay: DispatchTimeInterval
    private var sources: [DispatchSourceSignal]
    private let state = Mutex(State())

    init(
        relay: CommandSignalRelay,
        handler: @escaping @Sendable (SignalForwardingReport) -> Void,
    ) {
        self.handler = handler
        self.relay = relay
        #if DEBUG
            terminationHandler = nil
        #endif
        watchdogDelay = .seconds(10)
        sources = []
        sources = Self.observedSignals.map { commandSignal in
            let source = DispatchSource.makeSignalSource(
                signal: commandSignal.rawValue,
                queue: queue,
            )
            _ = Darwin.signal(commandSignal.rawValue, SIG_IGN)
            source.setEventHandler { [weak self] in
                // A dispatch signal source coalesces repeated delivery. Two
                // events are enough to preserve the supervisor's escalation.
                let count = min(max(source.data, 1), 2)
                self?.receive(commandSignal, count: count)
            }
            source.resume()
            return source
        }
    }

    #if DEBUG
        /// Builds a source without changing process-global signal dispositions.
        init(
            relay: CommandSignalRelay,
            watchdogDelay: DispatchTimeInterval,
            terminationHandler: @escaping @Sendable (CommandSignal) -> Void,
            handler: @escaping @Sendable (SignalForwardingReport) -> Void,
        ) {
            self.handler = handler
            self.relay = relay
            self.terminationHandler = terminationHandler
            self.watchdogDelay = watchdogDelay
            sources = []
        }
    #endif

    func receive(_ commandSignal: CommandSignal, count: UInt) {
        for _ in 0 ..< count {
            guard let report = relay.receiveSystemSignal(commandSignal) else {
                // EPIPE latches SIGPIPE synchronously so teardown cannot
                // overtake it. Its matching Dispatch delivery still owns the
                // hard deadline when another output task cannot be cancelled.
                armForcedTermination(for: commandSignal)
                continue
            }
            switch report.stage {
                case .first:
                    armForcedTermination(for: report.firstSignal)
                    handler(report)
                case .repeated:
                    _ = relay.forceTermination()
                    relay.waitUntilSafeToExitAfterForcedSignalBlocking()
                    terminate(with: report.firstSignal)
            }
        }
    }

    private func armForcedTermination(for commandSignal: CommandSignal) {
        let shouldSchedule = state.withLock { state in
            guard state.stopped == false, state.forcedTerminationArmed == false else {
                return false
            }
            state.forcedTerminationArmed = true
            return true
        }
        if shouldSchedule {
            queue.asyncAfter(deadline: .now() + watchdogDelay) { [weak self, relay] in
                guard let self,
                      state.withLock({ $0.stopped == false })
                else {
                    return
                }
                _ = relay.forceTermination()
                relay.waitUntilSafeToExitAfterForcedSignalBlocking()
                #if DEBUG
                    if let terminationHandler {
                        terminationHandler(commandSignal)
                        return
                    }
                #endif
                terminate(with: commandSignal)
            }
        }
    }

    func stop() {
        guard cancelSources() else { return }
        for commandSignal in Self.observedSignals {
            _ = Darwin.signal(commandSignal.rawValue, SIG_DFL)
        }
    }

    func terminate(with commandSignal: CommandSignal) -> Never {
        _ = cancelSources()
        var signalSet = sigset_t()
        sigemptyset(&signalSet)
        sigaddset(&signalSet, commandSignal.rawValue)
        _ = pthread_sigmask(SIG_UNBLOCK, &signalSet, nil)
        _ = Darwin.signal(commandSignal.rawValue, SIG_DFL)
        _ = Darwin.raise(commandSignal.rawValue)
        Darwin._exit(128 + commandSignal.rawValue)
    }

    private func cancelSources() -> Bool {
        let shouldCancel = state.withLock { state in
            guard state.stopped == false else { return false }
            state.stopped = true
            return true
        }
        guard shouldCancel else { return false }
        for source in sources {
            source.setEventHandler {}
            source.cancel()
        }
        return true
    }
}
