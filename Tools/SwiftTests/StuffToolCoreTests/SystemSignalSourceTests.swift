import Dispatch
@testable import StuffTool
@_spi(Testing) import StuffToolCore
import Synchronization
import Testing

struct SystemSignalSourceTests {
    @Test(.timeLimit(.minutes(1)))
    func coalescedPipeEchoArmsWatchdogWhileSiblingIgnoresCancellation() async {
        let forwardedSignals = Mutex<[CommandSignal]>([])
        let relay = CommandSignalRelay { _, signal in
            forwardedSignals.withLock { $0.append(signal) }
            return 0
        }
        let registration = relay.register(processGroupID: 101)
        defer { relay.unregister(registration) }

        let gate = CancellationUnawareSignalGate()
        let siblingCompleted = Mutex(false)
        let (siblingStarted, siblingStart) = AsyncStream.makeStream(of: Void.self)
        let sibling = Task {
            siblingStart.yield()
            await gate.wait()
            siblingCompleted.withLock { $0 = true }
        }
        var siblingStartIterator = siblingStarted.makeAsyncIterator()
        _ = await siblingStartIterator.next()
        siblingStart.finish()
        sibling.cancel()

        let forwardedReports = Mutex(0)
        let (terminations, termination) = AsyncStream.makeStream(
            of: CommandSignal.self,
            bufferingPolicy: .bufferingOldest(1),
        )
        let source = SystemSignalSource(
            relay: relay,
            watchdogDelay: .milliseconds(0),
            terminationHandler: { signal in
                termination.yield(signal)
                termination.finish()
            },
            handler: { _ in
                forwardedReports.withLock { $0 += 1 }
            },
        )
        defer {
            gate.open()
            sibling.cancel()
        }

        let errorReport = relay.receiveBrokenPipeError()
        source.receive(.brokenPipe, count: 1)
        var terminationIterator = terminations.makeAsyncIterator()
        let terminatedWith = await terminationIterator.next()

        #expect(errorReport?.stage == .first)
        #expect(terminatedWith == .brokenPipe)
        #expect(forwardedReports.withLock { $0 } == 0)
        #expect(siblingCompleted.withLock { $0 } == false)
        #expect(forwardedSignals.withLock { $0 } == [.brokenPipe, .kill])

        gate.open()
        await sibling.value
        #expect(siblingCompleted.withLock { $0 })
    }
}

private final class CancellationUnawareSignalGate: Sendable {
    private struct State {
        var isOpen = false
        var continuation: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func wait() async {
        await withCheckedContinuation { continuation in
            let shouldResume = state.withLock { state in
                guard state.isOpen == false else { return true }
                state.continuation = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func open() {
        let continuation = state.withLock { state in
            state.isOpen = true
            defer { state.continuation = nil }
            return state.continuation
        }
        continuation?.resume()
    }
}
