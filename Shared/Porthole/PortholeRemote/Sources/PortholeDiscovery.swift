import Foundation
import Network

public struct PortholeDiscoveredApplication: Sendable, Identifiable {
    public let name: String
    public let endpoint: NWEndpoint
    public var id: NWEndpoint {
        endpoint
    }
}

/// Discovery reveals service names only. TLS enrollment determines access.
public enum PortholeDiscovery {
    public static func applications()
        -> AsyncThrowingStream<[PortholeDiscoveredApplication], any Error>
    {
        AsyncThrowingStream { continuation in
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjour(type: "_porthole._tcp", domain: "local."),
                using: parameters,
            )
            browser.browseResultsChangedHandler = { results, _ in
                let applications = results.compactMap { result -> PortholeDiscoveredApplication? in
                    guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                    return PortholeDiscoveredApplication(name: name, endpoint: result.endpoint)
                }.sorted { $0.name < $1.name }
                continuation.yield(applications)
            }
            browser.stateUpdateHandler = { state in
                switch state {
                    case let .failed(error): continuation.finish(throwing: error)
                    case .cancelled: continuation.finish()
                    case .setup, .ready, .waiting: break
                    @unknown default: continuation
                    .finish(throwing: PortholeRemoteError.disconnected)
                }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: PortholeTLS.queue)
        }
    }
}
