import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionLoggingTests {
    @Test func successfulStartPublishesReadyBeforeHistoryPruningCompletes() async {
        let loggingSession = SuspendingDurableLoggingSession()
        let starter = ScriptedDurableLoggingStarter(result: .success(loggingSession))
        let session = ThrowSession.fixture(durableLoggingStarter: starter)

        session.startLaunch()
        await loggingSession.waitUntilPruningStarts()

        #expect(session.durableLoggingState == .ready)
        #expect(await starter.startCount == 1)

        session.startLaunch()
        #expect(await starter.startCount == 1)

        await loggingSession.resumePruning()
        await session.waitForDurableLoggingForTesting()
        #expect(await loggingSession.pruneCount == 1)
    }

    @Test func failedStartPublishesHonestDegradedState() async {
        let starter = ScriptedDurableLoggingStarter(result: .failure(.openFailed))
        let session = ThrowSession.fixture(durableLoggingStarter: starter)

        session.startLaunch()
        await session.waitForDurableLoggingForTesting()

        #expect(session.durableLoggingState == .failed)
        #expect(await starter.startCount == 1)
    }
}

private enum DurableLoggingTestFailure: Error {
    case openFailed
}

private actor ScriptedDurableLoggingStarter: ThrowDurableLoggingStarting {
    enum Result {
        case success(any ThrowDurableLoggingSession)
        case failure(DurableLoggingTestFailure)
    }

    let result: Result
    private(set) var startCount = 0

    init(result: Result) {
        self.result = result
    }

    func start() async throws -> any ThrowDurableLoggingSession {
        startCount += 1
        switch result {
            case let .success(session): return session
            case let .failure(error): throw error
        }
    }
}

private actor SuspendingDurableLoggingSession: ThrowDurableLoggingSession {
    private(set) var pruneCount = 0
    private var pruneStartedContinuation: CheckedContinuation<Void, Never>?
    private var pruneContinuation: CheckedContinuation<Void, Never>?

    func pruneHistory() async {
        pruneCount += 1
        pruneStartedContinuation?.resume()
        pruneStartedContinuation = nil
        await withCheckedContinuation { continuation in
            pruneContinuation = continuation
        }
    }

    func waitUntilPruningStarts() async {
        guard pruneCount == 0 else { return }
        await withCheckedContinuation { continuation in
            pruneStartedContinuation = continuation
        }
    }

    func resumePruning() {
        pruneContinuation?.resume()
        pruneContinuation = nil
    }
}
