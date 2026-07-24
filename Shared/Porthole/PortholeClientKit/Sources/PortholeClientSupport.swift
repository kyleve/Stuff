import Foundation
import Network
import os
import PortholeCore

/// Client-side logging (independent of Periscope — this is the Mac side).
enum PortholeClientLog {
    static let discovery = Logger(subsystem: "com.stuff.porthole.client", category: "discovery")
    static let session = Logger(subsystem: "com.stuff.porthole.client", category: "session")
}

/// Keychain service strings namespacing the two sides in a shared login keychain.
public enum PortholeCredentialService {
    public static let client = "com.stuff.porthole.client"
    public static let device = "com.stuff.porthole.device"
}

/// A default human-readable name for this Mac.
public func defaultPortholeClientName() -> String {
    ProcessInfo.processInfo.hostName
}

/// Opens an `NWConnection` to `endpoint` and wraps it in a frame transport.
func makeConnectionTransport(to endpoint: NWEndpoint) -> NWConnectionTransport {
    let parameters = NWParameters.tcp
    parameters.includePeerToPeer = true
    let connection = NWConnection(to: endpoint, using: parameters)
    let queue = DispatchQueue(label: "com.stuff.porthole.client.connection")
    return NWConnectionTransport(connection: connection, queue: queue)
}

struct PortholeClientTimeout: Error {}

/// Runs `operation` with a deadline, throwing `PortholeClientTimeout` if it
/// doesn't finish in time.
func withDeadline<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw PortholeClientTimeout()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
