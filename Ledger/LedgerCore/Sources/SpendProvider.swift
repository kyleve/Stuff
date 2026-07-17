import Foundation

/// A failure fetching spend from a ``SpendProvider``. Kept low-level and
/// transport-shaped; ``LedgerServices`` maps it into its user-facing
/// ``LedgerServices/LoadError``.
public enum SpendProviderError: Error, Equatable, Sendable {
    /// A non-2xx HTTP response, carrying the status code (401 = bad key).
    case http(Int)
    /// The transport failed (offline, DNS, TLS, timeout).
    case network(String)
    /// A 2xx response whose body didn't decode as a ``SpendResponse``.
    case decode(String)
}

/// The seam between ``LedgerServices`` and the network. Production uses
/// ``CursorSpendAPI``; tests conform ``ScriptedSpendProvider`` so no real HTTP
/// happens (per the "test doubles conform to the production protocol" rule).
public protocol SpendProvider: Sendable {
    /// Fetches the current-cycle team spend, authenticating with `apiKey`.
    /// Throws ``SpendProviderError`` on transport, HTTP, or decode failure.
    func fetchSpend(apiKey: String) async throws -> SpendResponse
}

/// The production ``SpendProvider``: `POST https://api.cursor.com/teams/spend`
/// with HTTP Basic auth (the Admin API key as the username, empty password),
/// exactly as the Admin API documents.
public struct CursorSpendAPI: SpendProvider {
    private let endpoint: URL
    private let session: URLSession

    /// The documented Admin API spend endpoint.
    public static let defaultEndpoint = URL(string: "https://api.cursor.com/teams/spend")!

    private static let logger = LedgerLog.channel(.spendAPI)

    public init(endpoint: URL = CursorSpendAPI.defaultEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func fetchSpend(apiKey: String) async throws -> SpendResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.basicAuthValue(apiKey: apiKey), forHTTPHeaderField: "Authorization")
        // An empty JSON object: the whole team, default sort/pagination. Ledger
        // filters to the signed-in user client-side rather than via searchTerm,
        // so a rename of the account can't hide the row.
        request.httpBody = Data("{}".utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            Self.logger.error("Spend request transport failed: \(error.localizedDescription)")
            throw SpendProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw SpendProviderError.network("Non-HTTP response")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            Self.logger.error("Spend request returned HTTP \(http.statusCode)")
            throw SpendProviderError.http(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(SpendResponse.self, from: data)
        } catch {
            Self.logger.error("Spend response failed to decode: \(error.localizedDescription)")
            throw SpendProviderError.decode(error.localizedDescription)
        }
    }

    /// `Basic base64(apiKey + ":")` — the API key is the username, the password
    /// is empty (mirrors `curl -u YOUR_API_KEY:`).
    @_spi(Testing)
    public static func basicAuthValue(apiKey: String) -> String {
        let token = Data("\(apiKey):".utf8).base64EncodedString()
        return "Basic \(token)"
    }
}
