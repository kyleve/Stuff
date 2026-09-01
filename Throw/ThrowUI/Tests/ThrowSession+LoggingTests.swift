import Foundation
@_spi(Testing) import PeriscopeCore
import Testing
@_spi(Testing) import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct ThrowSessionLoggingTests {
    @Test func coldLaunchFailureBeforeStoreAttachmentReachesTheStoreExactlyOnce() async throws {
        let system = Periscope(
            configuration: .init(
                recentBufferCapacity: 20,
                pendingBufferCapacity: 20,
                liveBufferCapacity: 20,
                flushThreshold: .error,
                redact: nil,
            ),
            sinks: [],
        )
        let store = try await PeriscopeStore.make(
            storage: .inMemory,
            session: .current(attributes: [:]),
        )
        let storeFactory = SuspendingPeriscopeStoreFactory(store: store)
        let starter = PeriscopeThrowDurableLoggingStarter(
            system: system,
            softwareCreditsLoadFailure: nil,
            now: { Date(timeIntervalSince1970: 1_787_594_400) },
            makeStore: { await storeFactory.makeStore() },
        )
        let preferenceStore = ThrowSessionLaunchPreferenceStore(
            result: .failure,
            suspendsLoad: false,
        )
        let session = ThrowSession.launchFixture(
            setupCompleted: true,
            preferenceStore: preferenceStore,
            credentialStore: ThrowSessionLaunchCredentialStore(
                failingID: nil,
                states: [:],
            ),
            durableLoggingStarter: starter,
            sessionFailureLogger: starter,
        )

        session.startLaunch()
        await storeFactory.waitUntilRequested()
        await session.waitForLaunchForTesting()

        #expect(session.launchState == .failed(.preferences))
        #expect(try await store.events(matching: LogQuery()).isEmpty)

        await storeFactory.resume()
        await session.waitForDurableLoggingForTesting()
        await system.flush()

        let storedFailures = try await store.events(matching: LogQuery()).filter {
            try $0.decode(ThrowSessionLogEvent.self) == .coldLaunchFailed(boundary: .preferences)
        }
        let storedFailure = try #require(storedFailures.first)
        #expect(storedFailures.count == 1)
        let attachments = try await store.attachments(forEvent: storedFailure.id)
        let attachment = try #require(attachments.first)
        #expect(attachments.count == 1)
        #expect(attachment.name == "launch-error")
        #expect(attachment.contentType == .json)
        let payload = try errorPayload(in: attachment)
        let expectedPayload = try errorPayload(
            in: .error(ThrowSessionLaunchTestFailure.preferences, name: "launch-error"),
        )
        #expect(payload == expectedPayload)
    }

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

    private func errorPayload(in attachment: LogAttachment) throws -> [String: String] {
        try JSONDecoder().decode([String: String].self, from: attachment.data)
    }
}

private actor SuspendingPeriscopeStoreFactory {
    private let store: PeriscopeStore
    private var requestStarted = false
    private var requestStartedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    init(store: PeriscopeStore) {
        self.store = store
    }

    func makeStore() async -> PeriscopeStore {
        requestStarted = true
        requestStartedContinuation?.resume()
        requestStartedContinuation = nil
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return store
    }

    func waitUntilRequested() async {
        guard requestStarted == false else { return }
        await withCheckedContinuation { continuation in
            requestStartedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
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
