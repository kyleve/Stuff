import Foundation

public enum HTTPMethod: String, Hashable, Sendable {
    case get = "GET"
}

public enum HTTPHeaderField: String, Hashable, Sendable {
    case accept = "Accept"
    case acceptEncoding = "Accept-Encoding"
    case acceptVersion = "Accept-Version"
    case authorization = "Authorization"
    case rapidAPIHost = "X-RapidAPI-Host"
    case rapidAPIKey = "X-RapidAPI-Key"
}

public struct HTTPRequest: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let method: HTTPMethod
    public let url: URL
    public let headers: [HTTPHeaderField: String]
    public let timeoutSeconds: TimeInterval

    public init(
        method: HTTPMethod,
        url: URL,
        headers: [HTTPHeaderField: String],
        timeoutSeconds: TimeInterval,
    ) {
        precondition(timeoutSeconds > 0 && timeoutSeconds.isFinite)
        self.method = method
        self.url = url
        self.headers = headers
        self.timeoutSeconds = timeoutSeconds
    }

    /// Deliberately excludes the URL (which may contain observer coordinates or
    /// a private receiver address) and every header value (which may be a key).
    public var description: String {
        "<HTTPRequest method=\(method.rawValue) url=<redacted> headers=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public struct HTTPResponse: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int, headers: [String: String], data: Data) {
        self.statusCode = statusCode
        self.headers = Dictionary(
            uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) },
        )
        self.data = data
    }

    public func headerValue(for name: String) -> String? {
        headers[name.lowercased()]
    }

    /// Response bodies and header values are never included in diagnostics.
    public var description: String {
        "<HTTPResponse status=\(statusCode) headers=\(headers.count) body=<redacted>>"
    }

    public var debugDescription: String {
        description
    }
}

public struct HTTPTransportFailure: Error, Equatable, Sendable {
    public let category: AircraftTransportErrorCategory

    public init(category: AircraftTransportErrorCategory) {
        self.category = category
    }
}

public protocol HTTPTransport: Sendable {
    func response(for request: HTTPRequest) async throws -> HTTPResponse
}

public enum HTTPNetworkScope: Equatable, Sendable {
    case internet
    case localNetwork
}

/// URLSession transport with ephemeral, no-cache sessions suitable for live
/// position feeds. Requests remain inspectable value types in tests.
public struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession
    private let networkScope: HTTPNetworkScope

    public init(session: URLSession, networkScope: HTTPNetworkScope) {
        self.session = session
        self.networkScope = networkScope
    }

    public static func makeCloud() -> URLSessionHTTPTransport {
        URLSessionHTTPTransport(
            session: makeSession(
                timeoutSeconds: 8,
                redirectDelegate: CloudRedirectRejectingDelegate(),
            ),
            networkScope: .internet,
        )
    }

    public static func makeLocal() -> URLSessionHTTPTransport {
        URLSessionHTTPTransport(
            session: makeSession(
                timeoutSeconds: 3,
                redirectDelegate: ReadsbRedirectValidatingDelegate(),
            ),
            networkScope: .localNetwork,
        )
    }

    public func response(for request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.timeoutInterval = request.timeoutSeconds
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        for (field, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: field.rawValue)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPTransportFailure(category: .invalidResponse)
            }
            let headers = httpResponse.allHeaderFields
                .reduce(into: [String: String]()) { result, item in
                    guard let key = item.key as? String else { return }
                    result[key] = String(describing: item.value)
                }
            return HTTPResponse(statusCode: httpResponse.statusCode, headers: headers, data: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as HTTPTransportFailure {
            throw failure
        } catch let error as URLError {
            let failure = try Self.failure(for: error, networkScope: networkScope)
            throw failure
        } catch {
            throw HTTPTransportFailure(category: .other)
        }
    }

    private static func makeSession(
        timeoutSeconds: TimeInterval,
        redirectDelegate: (any URLSessionTaskDelegate)?,
    ) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = timeoutSeconds
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil,
        )
    }

    static func failure(
        for error: URLError,
        networkScope: HTTPNetworkScope,
    ) throws -> HTTPTransportFailure {
        if error.code == .cancelled {
            try Task.checkCancellation()
        }
        return HTTPTransportFailure(
            category: category(for: error.code, networkScope: networkScope),
        )
    }

    static func category(
        for code: URLError.Code,
        networkScope: HTTPNetworkScope,
    ) -> AircraftTransportErrorCategory {
        if code == .notConnectedToInternet, networkScope == .localNetwork {
            return .localNetworkDenied
        }
        return switch code {
            case .cancelled:
                .cancelled
            case .timedOut:
                .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                .offline
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .secureConnectionFailed, .serverCertificateHasBadDate,
                 .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                .connection
            case .badURL, .unsupportedURL, .redirectToNonExistentLocation,
                 .badServerResponse, .zeroByteResource, .cannotDecodeRawData,
                 .cannotDecodeContentData, .cannotParseResponse,
                 .appTransportSecurityRequiresSecureConnection,
                 .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile,
                 .dataLengthExceedsMaximum, .internationalRoamingOff,
                 .callIsActive, .backgroundSessionRequiresSharedContainer,
                 .backgroundSessionInUseByAnotherProcess,
                 .backgroundSessionWasDisconnected,
                 .userAuthenticationRequired, .resourceUnavailable,
                 .cannotLoadFromNetwork, .downloadDecodingFailedMidStream,
                 .downloadDecodingFailedToComplete, .httpTooManyRedirects:
                .other
            // `URLError.Code` is a raw-value struct rather than an enum, so
            // callers can construct values beyond Foundation's named cases.
            default:
                .other
        }
    }
}

/// Cloud feeds reject redirects so an authentication header can never be
/// replayed to a redirected origin. The provider endpoint must answer directly.
final class CloudRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        completionHandler(nil)
    }
}

/// Reapplies the readsb URL policy to every redirected request before the
/// session is allowed to follow it.
final class ReadsbRedirectValidatingDelegate: NSObject, URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        guard let url = request.url,
              let originalURL = task.originalRequest?.url,
              let endpoint = ReadsbJSONEndpoint(url: originalURL)
        else {
            completionHandler(nil)
            return
        }
        do {
            _ = try ReadsbURLValidator.validateRedirectTarget(url, endpoint: endpoint)
            completionHandler(request)
        } catch {
            completionHandler(nil)
        }
    }
}
