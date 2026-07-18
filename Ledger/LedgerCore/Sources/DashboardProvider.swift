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
    /// The itemized invoice for a given month (`month` is 1-based) and year.
    func monthlyInvoice(month: Int, year: Int, token: SessionToken) async throws -> MonthlyInvoice
    /// Per-model usage aggregated over `[startDate, endDate]`.
    func aggregatedUsage(startDate: Date, endDate: Date, token: SessionToken) async throws
        -> AggregatedUsage
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

    public init(baseURL: URL = CursorDashboardAPI.defaultBaseURL, session: URLSession = .shared) {
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

    public func monthlyInvoice(
        month: Int,
        year: Int,
        token: SessionToken,
    ) async throws -> MonthlyInvoice {
        let body = try JSONSerialization.data(withJSONObject: [
            "month": month,
            "year": year,
            "includeUsageEvents": false,
        ])
        let request = makeRequest(
            path: "/api/dashboard/get-monthly-invoice",
            method: "POST",
            token: token,
            body: body,
        )
        return try await send(request, decoding: MonthlyInvoice.self)
    }

    public func aggregatedUsage(
        startDate: Date,
        endDate: Date,
        token: SessionToken,
    ) async throws -> AggregatedUsage {
        // `teamId: -1` selects individual usage; dates are epoch milliseconds.
        let body = try JSONSerialization.data(withJSONObject: [
            "teamId": -1,
            "startDate": Int(startDate.timeIntervalSince1970 * 1000),
            "endDate": Int(endDate.timeIntervalSince1970 * 1000),
        ])
        let request = makeRequest(
            path: "/api/dashboard/get-aggregated-usage-events",
            method: "POST",
            token: token,
            body: body,
        )
        return try await send(request, decoding: AggregatedUsage.self)
    }

    private func makeRequest(
        path: String,
        method: String,
        token: SessionToken,
        body: Data?,
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
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
