import Darwin
@_spi(Testing) import StuffToolCore
import Synchronization
import Testing

struct CommandSignalRelayTests {
    @Test func latchesFirstSignalUntilAProcessGroupRegisters() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()

        let report = relay.receive(.terminate)
        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        #expect(report.stage == .first)
        #expect(report.exitCode == 143)
        #expect(relay.firstSignal == .terminate)
        #expect(recorder.events == [SignalEvent(processGroupID: 101, signal: .terminate)])
    }

    @Test func forwardsTheFirstSignalToEveryRegisteredProcessGroup() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let second = relay.register(processGroupID: 202)
        let first = relay.register(processGroupID: 101)
        defer {
            relay.unregister(first)
            relay.unregister(second)
        }

        let report = relay.receive(.interrupt)

        #expect(report.stage == .first)
        #expect(report.failures.isEmpty)
        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .interrupt),
                SignalEvent(processGroupID: 202, signal: .interrupt),
            ],
        )
    }

    @Test func repeatedSignalForwardsExactlyThenKillsTheProcessGroup() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        _ = relay.receive(.interrupt)
        let report = relay.receive(.terminate)

        #expect(report.stage == .repeated)
        #expect(report.firstSignal == .interrupt)
        #expect(report.exitCode == 130)
        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .interrupt),
                SignalEvent(processGroupID: 101, signal: .terminate),
                SignalEvent(processGroupID: 101, signal: .kill),
            ],
        )
    }

    @Test func coalescesOnlyTheSystemPipeEchoPairedWithEPIPE() throws {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        let errorReport = try #require(relay.receiveBrokenPipeError())
        let echoReport = relay.receiveSystemSignal(.brokenPipe)
        let repeatedReport = try #require(relay.receiveSystemSignal(.brokenPipe))

        #expect(errorReport.stage == .first)
        #expect(echoReport == nil)
        #expect(repeatedReport.stage == .repeated)
        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .brokenPipe),
                SignalEvent(processGroupID: 101, signal: .brokenPipe),
                SignalEvent(processGroupID: 101, signal: .kill),
            ],
        )
    }

    @Test func forcingStateIsAppliedToAProcessGroupThatRegistersLater() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()

        _ = relay.receive(.interrupt)
        _ = relay.receive(.terminate)
        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .interrupt),
                SignalEvent(processGroupID: 101, signal: .terminate),
                SignalEvent(processGroupID: 101, signal: .kill),
            ],
        )
    }

    @Test func pendingSpawnBarrierWaitsForALatchedSignalToReachTheGroup() async {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let registration = relay.reserve()
        defer { relay.unregister(registration) }
        let waiter = Task {
            await relay.waitUntilSafeToExitAfterForcedSignal()
        }

        _ = relay.receive(.interrupt)
        _ = relay.receive(.terminate)
        relay.attach(registration, processGroupID: 101)
        await waiter.value

        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .interrupt),
                SignalEvent(processGroupID: 101, signal: .terminate),
                SignalEvent(processGroupID: 101, signal: .kill),
            ],
        )
    }

    @Test func failedPendingSpawnReleasesTheBarrier() async {
        let relay = SignalRecorder().makeRelay()
        let registration = relay.reserve()
        let waiter = Task {
            await relay.waitUntilSafeToExitAfterForcedSignal()
        }

        relay.unregister(registration)

        await waiter.value
    }

    @Test func forcedTerminationIsReplayedBeforeAPendingSpawnReleasesTheBarrier() async {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let registration = relay.reserve()
        defer { relay.unregister(registration) }
        let waiter = Task {
            await relay.waitUntilSafeToExitAfterForcedSignal()
        }

        _ = relay.receive(.interrupt)
        #expect(relay.forceTermination().isEmpty)
        relay.attach(registration, processGroupID: 101)
        await waiter.value

        #expect(
            recorder.events == [
                SignalEvent(processGroupID: 101, signal: .interrupt),
                SignalEvent(processGroupID: 101, signal: .kill),
            ],
        )
    }

    @Test func staleUnregisterDoesNotRemoveAReusedProcessGroupRegistration() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let stale = relay.register(processGroupID: 101)
        relay.unregister(stale)
        let current = relay.register(processGroupID: 101)
        defer { relay.unregister(current) }

        relay.unregister(stale)
        _ = relay.receive(.interrupt)

        #expect(recorder.events == [SignalEvent(processGroupID: 101, signal: .interrupt)])
    }

    @Test func unregisterStopsLaterSignalForwarding() {
        let recorder = SignalRecorder()
        let relay = recorder.makeRelay()
        let registration = relay.register(processGroupID: 101)

        relay.unregister(registration)
        _ = relay.receive(.interrupt)

        #expect(recorder.events.isEmpty)
    }

    @Test func ignoresExitedGroupsAndReportsOtherForwardingFailures() {
        let recorder = SignalRecorder { processGroupID, _ in
            processGroupID == 101 ? ESRCH : EPERM
        }
        let relay = recorder.makeRelay()
        let exited = relay.register(processGroupID: 101)
        let forbidden = relay.register(processGroupID: 202)
        defer {
            relay.unregister(exited)
            relay.unregister(forbidden)
        }

        let report = relay.receive(.terminate)

        #expect(report.failures.map(\.processGroupID) == [202])
        #expect(report.failures.map(\.signal) == [.terminate])
        #expect(report.failures.map(\.errorNumber) == [EPERM])
        #expect(relay.forwardingFailures == report.failures)
    }

    @Test func recordsFailuresWhileReplayingALatchedSignal() {
        let recorder = SignalRecorder { _, _ in EPERM }
        let relay = recorder.makeRelay()
        _ = relay.receive(.interrupt)

        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        #expect(relay.forwardingFailures.map(\.processGroupID) == [101])
        #expect(relay.forwardingFailures.map(\.signal) == [.interrupt])
        #expect(relay.forwardingFailures.map(\.errorNumber) == [EPERM])
    }

    @Test func taskLocalRelayIsScopedAndInheritedByChildTasks() async {
        let relay = SignalRecorder().makeRelay()

        #expect(CommandSignalRelay.current == nil)
        await CommandSignalRelay.$current.withValue(relay) {
            #expect(CommandSignalRelay.current === relay)
            let inherited = await Task {
                CommandSignalRelay.current === relay
            }.value
            #expect(inherited)
        }
        #expect(CommandSignalRelay.current == nil)
    }
}

private struct SignalEvent: Equatable {
    let processGroupID: Int32
    let signal: CommandSignal
}

private final class SignalRecorder: Sendable {
    private let storage = Mutex<[SignalEvent]>([])
    private let errorNumber: @Sendable (Int32, CommandSignal) -> Int32

    init(
        errorNumber: @escaping @Sendable (Int32, CommandSignal) -> Int32 = { _, _ in 0 },
    ) {
        self.errorNumber = errorNumber
    }

    func makeRelay() -> CommandSignalRelay {
        CommandSignalRelay { [self] processGroupID, signal in
            storage.withLock {
                $0.append(SignalEvent(processGroupID: processGroupID, signal: signal))
            }
            return errorNumber(processGroupID, signal)
        }
    }

    var events: [SignalEvent] {
        storage.withLock { $0 }
    }
}
