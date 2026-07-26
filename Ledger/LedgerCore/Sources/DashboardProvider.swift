import Foundation

/// A failure talking to the Cursor dashboard API. Kept transport-shaped;
/// ``LedgerServices`` maps it into its user-facing ``LedgerServices/LoadError``.
public enum DashboardError: Error, Equatable, Sendable {
    /// HTTP 401 — the session token is missing, malformed, or expired.
    case notAuthenticated
    /// Another non-2xx HTTP response, carrying the status code.
    case http(Int)
    /// The transport failed (offline, DNS, TLS, timeout).
    case network(String)
    /// A 2xx response whose body didn't decode.
    case decode(String)
}

/// The seam between ``LedgerServices`` and Cursor's dashboard API. Production
/// uses ``CursorDashboardAPI``; tests conform ``ScriptedDashboardProvider``.
public protocol DashboardProvider: Sendable {
    /// The current billing cycle's usage summary.
    func usageSummary(token: SessionToken) async throws -> UsageSummary
    /// One page of individual usage events in `[startDate, endDate]` (newest
    /// first). Pages are 1-based.
    func usageEvents(
        startDate: Date,
        endDate: Date,
        page: Int,
        pageSize: Int,
        token: SessionToken,
    ) async throws -> UsageEventsPage
}

/// The production ``DashboardProvider``: the same undocumented endpoints the
/// `cursor.com/dashboard/usage` page calls, authenticated with the
/// `WorkosCursorSessionToken` cookie.
public struct CursorDashboardAPI: DashboardProvider {
    private let baseURL: URL
    private let session: URLSession

    /// The dashboard's origin.
    public static let defaultBaseURL = URL(string: "https://cursor.com")!

    private static let logger = LedgerLog.channel(.spendAPI)

    /// A session dedicated to the dashboard API: ephemeral with **no cookie
    /// storage**, because auth is the `Cookie` header we set explicitly. Left
    /// to the shared session, URLSession's own cookie handling could store a
    /// `Set-Cookie` from a response and then send *that* in place of the token
    /// we resolved — an intermittent 401 that would read as "session expired"
    /// with no trace of the substitution. The timeout is well under the 60s
    /// default since a per-model fetch chains several requests.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }

    public init(
        baseURL: URL = CursorDashboardAPI.defaultBaseURL,
        session: URLSession = CursorDashboardAPI.makeSession(),
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func usageSummary(token: SessionToken) async throws -> UsageSummary {
        let request = makeRequest(
            path: "/api/usage-summary",
            method: "GET",
            token: token,
            body: nil,
        )
        return try await send(request, decoding: UsageSummary.self)
    }

    public func usageEvents(
        startDate: Date,
        endDate: Date,
        page: Int,
        pageSize: Int,
        token: SessionToken,
    ) async throws -> UsageEventsPage {
        // Dates are epoch milliseconds. Note: this endpoint must NOT be sent a
        // `teamId` for an individual account — including it 401s.
        let body = try JSONSerialization.data(withJSONObject: [
            "startDate": Int(startDate.timeIntervalSince1970 * 1000),
            "endDate": Int(endDate.timeIntervalSince1970 * 1000),
            "page": page,
            "pageSize": pageSize,
        ])
        let request = makeRequest(
            path: "/api/dashboard/get-filtered-usage-events",
            method: "POST",
            token: token,
            body: body,
        )
        return try await send(request, decoding: UsageEventsPage.self)
    }

    private func makeRequest(
        path: String,
        method: String,
        token: SessionToken,
        body: Data?,
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        // Our `Cookie` header is the only credential; never let URLSession
        // substitute a stored one (see `makeSession()`).
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue("https://cursor.com/dashboard?tab=usage", forHTTPHeaderField: "Referer")
        request.setValue(
            "WorkosCursorSessionToken=\(token.cookieValue)",
            forHTTPHeaderField: "Cookie",
        )
        request.httpBody = body
        return request
    }

    private func send<Response: Decodable>(
        _ request: URLRequest,
        decoding _: Response.Type,
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("Dashboard request transport failed: \(error.localizedDescription)")
            throw DashboardError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DashboardError.network("Non-HTTP response")
        }
        if http.statusCode == 401 {
            throw DashboardError.notAuthenticated
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            Self.logger.error("Dashboard request returned HTTP \(http.statusCode)")
            throw DashboardError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            Self.logger.error("Dashboard response failed to decode: \(error.localizedDescription)")
            throw DashboardError.decode(error.localizedDescription)
        }
    }
}
