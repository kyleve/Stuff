import Darwin
import Dispatch
import Synchronization

/// A POSIX signal that can be forwarded to an isolated command process group.
public enum CommandSignal: Int32, Hashable, Sendable {
    case hangup = 1
    case interrupt = 2
    case quit = 3
    case kill = 9
    case brokenPipe = 13
    case terminate = 15
}

/// A failure to forward a signal to a process group that was still registered.
public struct SignalForwardingFailure: Equatable, Sendable {
    public let processGroupID: Int32
    public let signal: CommandSignal
    public let errorNumber: Int32
}

/// Describes how a received command signal changed relay state.
public struct SignalForwardingReport: Equatable, Sendable {
    public enum Stage: Equatable, Sendable {
        case first
        case repeated
    }

    public let stage: Stage
    public let firstSignal: CommandSignal
    public let failures: [SignalForwardingFailure]

    public var exitCode: Int32 {
        128 + firstSignal.rawValue
    }
}

/// Relays command-task signals to registered, independently sessioned process groups.
public final class CommandSignalRelay: Sendable {
    public struct Registration: Hashable, Sendable {
        fileprivate let id: UInt64
    }

    @TaskLocal public static var current: CommandSignalRelay?

    private enum RegisteredCommand {
        case spawning(cancellationRequested: Bool)
        case running(
            processGroupID: Int32,
            cancellationRequested: Bool,
            forcedTerminationScheduled: Bool,
        )
        case finishing
    }

    private struct ForcedExitWaiters {
        var asynchronous: [CheckedContinuation<Void, Never>] = []
        var blocking: [DispatchSemaphore] = []

        func resume() {
            for continuation in asynchronous {
                continuation.resume()
            }
            for semaphore in blocking {
                semaphore.signal()
            }
        }
    }

    private struct State {
        var latchedSignals: [CommandSignal] = []
        var nextRegistrationID: UInt64 = 0
        var commands: [Registration: RegisteredCommand] = [:]
        var forcedExitWaiters = ForcedExitWaiters()
        var expectedSystemSignalEchoes: [CommandSignal: Int] = [:]
        var failures: [SignalForwardingFailure] = []
    }

    private let state = Mutex(State())
    private let signalProcessGroup: @Sendable (Int32, CommandSignal) -> Int32

    public init() {
        signalProcessGroup = { processGroupID, signal in
            guard Darwin.kill(-processGroupID, signal.rawValue) == 0 else {
                return errno
            }
            return 0
        }
    }

    @_spi(Testing)
    public init(
        signalProcessGroup: @escaping @Sendable (Int32, CommandSignal) -> Int32,
    ) {
        self.signalProcessGroup = signalProcessGroup
    }

    /// Reserves relay ownership before a command can create an isolated session.
    @_spi(Testing)
    public func reserve() -> Registration {
        state.withLock { state in
            let registration = nextRegistration(in: &state)
            state.commands[registration] = .spawning(cancellationRequested: false)
            return registration
        }
    }

    /// Attaches the spawned process group while its leader cannot be reaped.
    @_spi(Testing)
    public func attach(
        _ registration: Registration,
        processGroupID: Int32,
    ) {
        precondition(processGroupID > 1, "refusing to signal an unsafe process group")
        let outcome = state.withLock { state in
            guard case let .spawning(cancellationRequested) = state.commands[registration] else {
                preconditionFailure("attaching an unknown command registration")
            }
            state.commands[registration] = .running(
                processGroupID: processGroupID,
                cancellationRequested: cancellationRequested,
                forcedTerminationScheduled: cancellationRequested,
            )

            let failures = forward(state.latchedSignals, to: processGroupID)
            state.failures.append(contentsOf: failures)
            return (
                cancellationRequested,
                takeForcedExitWaitersIfReady(in: &state),
            )
        }
        if outcome.0 {
            scheduleForcedTermination(for: registration)
        }
        outcome.1.resume()
    }

    /// Registers an already-spawned group. Prefer `reserve()` before spawning.
    @_spi(Testing)
    public func register(processGroupID: Int32) -> Registration {
        let registration = reserve()
        attach(registration, processGroupID: processGroupID)
        return registration
    }

    /// Stops forwarding before the process-group leader can be reaped and its PID reused.
    @_spi(Testing)
    public func unregister(_ registration: Registration) {
        complete(registration)
    }

    /// Waits until every spawn is attached and every reaping window has closed.
    public func waitUntilSafeToExitAfterForcedSignal() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                guard hasForcedExitBlocker(state) else { return true }
                state.forcedExitWaiters.asynchronous.append(continuation)
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    /// A Dispatch-safe variant for the process-wide last-resort watchdog.
    public func waitUntilSafeToExitAfterForcedSignalBlocking() {
        let semaphore = DispatchSemaphore(value: 0)
        let shouldWait = state.withLock { state in
            guard hasForcedExitBlocker(state) else { return false }
            state.forcedExitWaiters.blocking.append(semaphore)
            return true
        }
        if shouldWait {
            semaphore.wait()
        }
    }

    /// Clears the live group before the body returns and the leader can be reaped.
    func finish(_ registration: Registration) {
        let waiters = state.withLock { state in
            guard case let .running(processGroupID, cancellationRequested, _) =
                state.commands[registration]
            else {
                return ForcedExitWaiters()
            }
            if cancellationRequested || state.latchedSignals.isEmpty == false {
                let failures = forward([.kill], to: processGroupID)
                state.failures.append(contentsOf: failures)
            }
            state.commands[registration] = .finishing
            return takeForcedExitWaitersIfReady(in: &state)
        }
        waiters.resume()
    }

    /// Marks a spawn or teardown complete after `Subprocess.run` returns.
    func complete(_ registration: Registration) {
        let waiters = state.withLock { state in
            state.commands.removeValue(forKey: registration)
            return takeForcedExitWaitersIfReady(in: &state)
        }
        waiters.resume()
    }

    /// Latches the first signal and escalates every later signal with `SIGKILL`.
    @_spi(Testing)
    public func receive(_ signal: CommandSignal) -> SignalForwardingReport {
        state.withLock { state in
            receive(signal, state: &state)
        }
    }

    /// Coalesces the SIGPIPE delivery paired with a synchronously observed EPIPE.
    public func receiveSystemSignal(
        _ signal: CommandSignal,
    ) -> SignalForwardingReport? {
        state.withLock { state in
            if let echoCount = state.expectedSystemSignalEchoes[signal], echoCount > 0 {
                if echoCount == 1 {
                    state.expectedSystemSignalEchoes.removeValue(forKey: signal)
                } else {
                    state.expectedSystemSignalEchoes[signal] = echoCount - 1
                }
                return nil
            }
            return receive(signal, state: &state)
        }
    }

    /// Latches a pipe failure before command teardown can overtake SIGPIPE.
    @discardableResult
    public func receiveBrokenPipeError() -> SignalForwardingReport? {
        state.withLock { state in
            guard state.latchedSignals.isEmpty else { return nil }
            state.expectedSystemSignalEchoes[.brokenPipe, default: 0] += 1
            return receive(.brokenPipe, state: &state)
        }
    }

    /// Immediately kills every group that is still safe to signal.
    public func forceTermination() -> [SignalForwardingFailure] {
        state.withLock { state in
            if state.latchedSignals.contains(.kill) == false {
                state.latchedSignals.append(.kill)
            }
            let failures = processGroups(in: state).flatMap { processGroupID in
                forward([.kill], to: processGroupID)
            }
            state.failures.append(contentsOf: failures)
            return failures
        }
    }

    public var firstSignal: CommandSignal? {
        state.withLock { $0.latchedSignals.first }
    }

    public var forwardingFailures: [SignalForwardingFailure] {
        state.withLock { $0.failures }
    }

    /// Starts a final group kill if task cancellation cannot unblock the command body.
    func beginCancellation(_ registration: Registration) {
        let shouldSchedule = state.withLock { state in
            switch state.commands[registration] {
                case .spawning:
                    state.commands[registration] = .spawning(cancellationRequested: true)
                    return false
                case let .running(processGroupID, _, forcedTerminationScheduled):
                    state.commands[registration] = .running(
                        processGroupID: processGroupID,
                        cancellationRequested: true,
                        forcedTerminationScheduled: true,
                    )
                    return forcedTerminationScheduled == false
                case .finishing, nil:
                    return false
            }
        }
        if shouldSchedule {
            scheduleForcedTermination(for: registration)
        }
    }

    private func nextRegistration(in state: inout State) -> Registration {
        repeat {
            state.nextRegistrationID &+= 1
        } while state.commands[Registration(id: state.nextRegistrationID)] != nil
        return Registration(id: state.nextRegistrationID)
    }

    private func receive(
        _ signal: CommandSignal,
        state: inout State,
    ) -> SignalForwardingReport {
        let stage: SignalForwardingReport.Stage
        let firstSignal: CommandSignal
        let signals: [CommandSignal]
        if let first = state.latchedSignals.first {
            stage = .repeated
            firstSignal = first
            signals = [signal, .kill]
            state.latchedSignals = [first, signal, .kill]
        } else {
            stage = .first
            firstSignal = signal
            signals = [signal]
            state.latchedSignals = signals
        }

        let failures = processGroups(in: state).flatMap { processGroupID in
            forward(signals, to: processGroupID)
        }
        state.failures.append(contentsOf: failures)
        return SignalForwardingReport(
            stage: stage,
            firstSignal: firstSignal,
            failures: failures,
        )
    }

    private func processGroups(in state: State) -> [Int32] {
        let processGroups = state.commands.values.compactMap { command -> Int32? in
            guard case let .running(processGroupID, _, _) = command else { return nil }
            return processGroupID
        }
        return Set(processGroups).sorted()
    }

    private func scheduleForcedTermination(for registration: Registration) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 4) { [self] in
            state.withLock { state in
                guard case let .running(processGroupID, _, _) =
                    state.commands[registration]
                else {
                    return
                }
                let failures = forward([.kill], to: processGroupID)
                state.failures.append(contentsOf: failures)
            }
        }
    }

    private func hasForcedExitBlocker(_ state: State) -> Bool {
        state.commands.values.contains { command in
            switch command {
                case .spawning, .finishing: true
                case .running: false
            }
        }
    }

    private func takeForcedExitWaitersIfReady(
        in state: inout State,
    ) -> ForcedExitWaiters {
        guard hasForcedExitBlocker(state) == false else { return ForcedExitWaiters() }
        defer { state.forcedExitWaiters = ForcedExitWaiters() }
        return state.forcedExitWaiters
    }

    private func forward(
        _ signals: [CommandSignal],
        to processGroupID: Int32,
    ) -> [SignalForwardingFailure] {
        signals.compactMap { signal in
            let errorNumber = signalProcessGroup(processGroupID, signal)
            guard errorNumber != 0, errorNumber != ESRCH else { return nil }
            return SignalForwardingFailure(
                processGroupID: processGroupID,
                signal: signal,
                errorNumber: errorNumber,
            )
        }
    }
}
