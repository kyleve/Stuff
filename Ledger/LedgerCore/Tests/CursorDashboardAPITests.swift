import Foundation
@_spi(Testing) import LedgerCore
import Testing

/// Covers the wire shape of ``CursorDashboardAPI`` — the details that are only
/// visible to the server and so can't fail a normal test: which keys the body
/// carries, the units of the dates, and the auth header. Each has already cost
/// a real 401 during development.
@Suite(.serialized)
struct CursorDashboardAPITests {
    private let token = SessionToken(cookieValue: "user_X::jwt")

    private func makeAPI() -> CursorDashboardAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return CursorDashboardAPI(session: URLSession(configuration: configuration))
    }

    @Test func usageEventsSendsNoTeamID() async throws {
        StubURLProtocol.reset(body: DashboardFixture.usageEventsJSON)
        _ = try await makeAPI().usageEvents(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            page: 2,
            pageSize: 250,
            token: token,
        )

        let body = try #require(StubURLProtocol.lastBodyObject)
        // Sending `teamId` on this endpoint 401s an individual account. The
        // sibling aggregated endpoint *did* want it, so it looks plausible —
        // hence this guard.
        #expect(body["teamId"] == nil)
        #expect(body["page"] as? Int == 2)
        #expect(body["pageSize"] as? Int == 250)
    }

    @Test func usageEventsSendsDatesAsEpochMilliseconds() async throws {
        StubURLProtocol.reset(body: DashboardFixture.usageEventsJSON)
        _ = try await makeAPI().usageEvents(
            startDate: Date(timeIntervalSince1970: 1000),
            endDate: Date(timeIntervalSince1970: 2000),
            page: 1,
            pageSize: 250,
            token: token,
        )

        let body = try #require(StubURLProtocol.lastBodyObject)
        // Seconds instead of milliseconds would silently query 1970 and return
        // an empty window rather than failing.
        #expect(body["startDate"] as? Int == 1_000_000)
        #expect(body["endDate"] as? Int == 2_000_000)
    }

    @Test func sendsTheSessionCookieAndOptsOutOfCookieHandling() async throws {
        StubURLProtocol.reset(body: DashboardFixture.usageSummaryJSON)
        _ = try await makeAPI().usageSummary(token: token)

        let request = try #require(StubURLProtocol.lastRequest)
        #expect(request
            .value(forHTTPHeaderField: "Cookie") == "WorkosCursorSessionToken=user_X::jwt")
        // Auth is this header alone; URLSession must never substitute a stored
        // cookie for it.
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.url?.path == "/api/usage-summary")
        #expect(request.httpMethod == "GET")
    }

    @Test func mapsA401ToNotAuthenticated() async {
        StubURLProtocol.reset(body: "{}", statusCode: 401)
        await #expect(throws: DashboardError.notAuthenticated) {
            try await makeAPI().usageSummary(token: token)
        }
    }

    @Test func mapsOtherFailureStatusesToHTTP() async {
        StubURLProtocol.reset(body: "{}", statusCode: 503)
        await #expect(throws: DashboardError.http(503)) {
            try await makeAPI().usageSummary(token: token)
        }
    }

    @Test func mapsAnUndecodableBodyToDecode() async {
        StubURLProtocol.reset(body: "not json")
        await #expect(throws: DashboardError.self) {
            try await makeAPI().usageSummary(token: token)
        }
    }
}

/// A `URLProtocol` that answers every request from a canned response and
/// records what was sent. Serialized suite + reset-per-test keeps the shared
/// state safe (URLProtocol registration is inherently process-global).
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private nonisolated(unsafe) static let lock = NSLock()
    private nonisolated(unsafe) static var responseBody = "{}"
    private nonisolated(unsafe) static var responseStatus = 200
    private nonisolated(unsafe) static var captured: URLRequest?
    private nonisolated(unsafe) static var capturedBody: Data?

    static func reset(body: String, statusCode: Int = 200) {
        lock.withLock {
            responseBody = body
            responseStatus = statusCode
            captured = nil
            capturedBody = nil
        }
    }

    /// The most recent request (headers, URL, method).
    static var lastRequest: URLRequest? {
        lock.withLock { captured }
    }

    /// The most recent request body, decoded as a JSON object.
    static var lastBodyObject: [String: Any]? {
        guard let data = lock.withLock({ capturedBody }) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // `URLProtocol` strips `httpBody` from the request it hands back, so
        // read it from the body stream when present.
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain)
        Self.lock.withLock {
            Self.captured = request
            Self.capturedBody = body
        }

        let (status, text) = Self.lock.withLock { (Self.responseStatus, Self.responseBody) }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil,
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 4096
        var buffer = [UInt8](repeating: 0, count: size)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: size)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
