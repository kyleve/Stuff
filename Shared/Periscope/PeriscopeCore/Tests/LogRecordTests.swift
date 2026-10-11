import Foundation
import PeriscopeCore
import Testing

struct LogRecordTests {
    @Test func exposesItsEventDerivedFields() {
        let scope = LogScope.root(named: "photos")
        let record = LogRecord(
            date: Date(timeIntervalSince1970: 100),
            event: makePhotoEvent("p1"),
            scopes: [scope.id],
        )
        #expect(record.level == .notice)
        #expect(record.message == "photo p1")
        #expect(record.eventName == "PhotoLogs.event")
        #expect(record.eventVersion == 1)
        #expect(record.scopes == [scope.id])
    }
}
