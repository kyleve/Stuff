import Foundation

public protocol UpdateFetching: Sendable {
    func fetch(from url: URL) async throws -> UpdateCatalog
}

/// Credential-free HTTPS reader. Invalid feeds never replace the last successful result.
public struct UpdateClient: UpdateFetching {
    /// Response failures retain the HTTP status separately from transport and feed errors.
    public enum FetchError: Error, Equatable {
        case invalidResponse
        case unexpectedLocation
        case httpStatus(Int)
        case responseTooLarge
    }

    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func fetch(from url: URL) async throws -> UpdateCatalog {
        let request = URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 15,
        )
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw FetchError.invalidResponse }
        guard response.url?.scheme == "https", response.url?.host == url.host else {
            throw FetchError.unexpectedLocation
        }
        guard response.statusCode == 200 else { throw FetchError.httpStatus(response.statusCode) }
        guard data.count <= 1_000_000 else { throw FetchError.responseTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(UpdateCatalog.self, from: data)
        try catalog.validate(feedURL: url)
        return catalog
    }
}
