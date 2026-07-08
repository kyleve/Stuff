import Foundation
import PeriscopeCore
@testable import PeriscopeTools
import Testing

@MainActor
struct LocalNotificationAlertHandlerTests {
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
}
