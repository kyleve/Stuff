import Foundation
import os
import PeriscopeCore
@testable import PeriscopeTools
import Testing
import UserNotifications

private struct FakeAuthorizationError: Error {}

/// An `AlertNotificationCenter` that records authorization traffic and
/// posted identifiers, with scriptable grant/failure outcomes.
private final class FakeAlertCenter: AlertNotificationCenter, Sendable {
    private struct State {
        var grantsAuthorization = true
        var authorizationFails = false
        var authorizationRequestCount = 0
        var addedIdentifiers: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var authorizationRequestCount: Int {
        state.withLock(\.authorizationRequestCount)
    }

    var addedIdentifiers: [String] {
        state.withLock(\.addedIdentifiers)
    }

    func setGrantsAuthorization(_ grants: Bool) {
        state.withLock { $0.grantsAuthorization = grants }
    }

    func setAuthorizationFails(_ fails: Bool) {
        state.withLock { $0.authorizationFails = fails }
    }

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        try state.withLock { state in
            state.authorizationRequestCount += 1
            if state.authorizationFails {
                throw FakeAuthorizationError()
            }
            return state.grantsAuthorization
        }
    }

    func add(_ request: sending UNNotificationRequest) async throws {
        let identifier = request.identifier
        state.withLock { $0.addedIdentifiers.append(identifier) }
    }
}

@MainActor
struct LocalNotificationAlertHandlerTests {
    private let center = FakeAlertCenter()

    private func makeRecord(_ message: String) -> LogRecord {
        LogRecord(
            date: Date(),
            event: Message(level: .error, message),
            scopes: [LogScope.root(named: "app").id],
        )
    }

    @Test func requestsCarryTheRecordsSeverityAndMessage() {
        let record = LogRecord(
            date: Date(),
            event: Message(level: .error, "Upload failed"),
            scopes: [LogScope.root(named: "app").id],
        )

        let request = LocalNotificationAlertHandler.request(for: record)

        #expect(request.content.title == "Error: message")
        #expect(request.content.body == "Upload failed")
        #expect(request.identifier == "periscope-alert-\(record.id.uuidString)")
        #expect(request.trigger == nil)
    }

    @Test func authorizationIsRequestedOnceAcrossPosts() async {
        let handler = LocalNotificationAlertHandler(center: center)

        await handler.post(for: makeRecord("one"))
        await handler.post(for: makeRecord("two"))
        await handler.post(for: makeRecord("three"))

        #expect(center.authorizationRequestCount == 1)
        #expect(center.addedIdentifiers.count == 3)
    }

    @Test func deniedAuthorizationGoesQuietWithoutReasking() async {
        center.setGrantsAuthorization(false)
        let handler = LocalNotificationAlertHandler(center: center)

        await handler.post(for: makeRecord("one"))
        await handler.post(for: makeRecord("two"))

        #expect(center.authorizationRequestCount == 1)
        #expect(center.addedIdentifiers.isEmpty)
    }

    @Test func failedAuthorizationRequestsRetryOnTheNextAlert() async {
        center.setAuthorizationFails(true)
        let handler = LocalNotificationAlertHandler(center: center)

        await handler.post(for: makeRecord("during failure"))
        #expect(center.authorizationRequestCount == 1)
        #expect(center.addedIdentifiers.isEmpty)

        // A transient failure must not be cached as denial.
        center.setAuthorizationFails(false)
        await handler.post(for: makeRecord("after recovery"))
        #expect(center.authorizationRequestCount == 2)
        #expect(center.addedIdentifiers.count == 1)
    }
}
