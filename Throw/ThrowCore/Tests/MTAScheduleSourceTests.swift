import Foundation
import Testing
@testable import ThrowCore

struct MTAScheduleSourceTests {
    @Test func requestUsesOfficialSupplementedScheduleAndZipAcceptHeader() async throws {
        let transport = ScriptedHTTPTransport(outcomes: [.response(
            ThrowCoreFixture.response(statusCode: 503, data: Data()),
        )])
        let source = MTAScheduleSource(transport: transport)
        await #expect(throws: TransitDataError.server(statusCode: 503)) {
            try await source.schedule(fetchedAt: ThrowCoreFixture.date)
        }
        let request = try #require(await transport.recordedRequests().first)
        #expect(request.url == MTAScheduleSource.supplementedScheduleURL)
        #expect(request.headers[.accept] == "application/zip")
    }

    @Test func decoderRejectsNonZipData() {
        #expect(throws: TransitDataError.invalidSchedule) {
            try MTAScheduleSource.decode(
                Data("not-a-zip".utf8),
                fetchedAt: ThrowCoreFixture.date,
                revision: "bad",
            )
        }
    }
}
