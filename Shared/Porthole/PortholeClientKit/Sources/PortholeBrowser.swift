import Foundation
import Network
import PortholeCore

/// Discovers Porthole-advertising apps on the local network via Bonjour. Each
/// change re-yields the full current set.
public final class PortholeBrowser: @unchecked Sendable {
    private let serviceType: String

    public init(serviceType: String = "_porthole._tcp") {
        self.serviceType = serviceType
    }

    /// A stream of the current set of discovered apps, updated as they come and
    /// go. Cancelling the stream stops browsing.
    public func discovered() -> AsyncStream<[DiscoveredApp]> {
        AsyncStream { continuation in
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: serviceType, domain: nil),
                using: parameters,
            )
            browser.browseResultsChangedHandler = { results, _ in
                continuation.yield(results.compactMap { Self.discoveredApp(from: $0) })
            }
            browser.stateUpdateHandler = { state in
                if case let .failed(error) = state {
                    PortholeClientLog.discovery
                        .error("Browser failed: \(String(describing: error), privacy: .public)")
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in browser.cancel() }
            browser.start(queue: .global(qos: .userInitiated))
        }
    }

    private static func discoveredApp(from result: NWBrowser.Result) -> DiscoveredApp? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        var txt: [String: String] = [:]
        if case let .bonjour(record) = result.metadata {
            txt = record.dictionary
        }
        return DiscoveredApp(
            endpointName: name,
            appName: txt["name"] ?? name,
            bundleID: txt["bundle"] ?? "",
            deviceName: txt["device"] ?? "",
            protocolVersion: Int(txt["ver"] ?? "") ?? 0,
            endpoint: result.endpoint,
        )
    }
}
