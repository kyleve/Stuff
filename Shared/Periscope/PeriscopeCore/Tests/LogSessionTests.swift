import Foundation
import PeriscopeCore
import Testing

struct LogSessionTests {
    @Test func currentDescribesThisLaunch() {
        let session = LogSession.current()
        #expect(!session.appVersion.isEmpty)
        #expect(!session.buildNumber.isEmpty)
        #expect(!session.osVersion.isEmpty)
        #expect(!session.deviceModel.isEmpty)
    }

    @Test func eachCurrentSessionIsDistinct() {
        #expect(LogSession.current().id != LogSession.current().id)
    }

    @Test func roundTripsThroughCodable() throws {
        let session = LogSession.fixture()
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LogSession.self, from: data)
        #expect(decoded == session)
    }
}
