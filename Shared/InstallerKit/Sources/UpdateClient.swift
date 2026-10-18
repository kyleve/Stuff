import Foundation

public protocol UpdateFetching: Sendable {
    func fetch(from url: URL) async throws -> UpdateCatalog
}

/// Credential-free HTTPS reader. Invalid feeds never replace the last successful result.
public struct UpdateClient: UpdateFetching {
    public enum FetchError: Error {
        case invalidResponse
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
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200, response.url?.scheme == "https",
              response.url?.host == url.host, data.count <= 1_000_000
        else { throw FetchError.invalidResponse }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(UpdateCatalog.self, from: data)
        try catalog.validate(feedURL: url)
        return catalog
    }
}
