import Foundation

/// How a host app configures its ``Porthole`` runtime. `appName` is required;
/// the rest are convenience defaults (the app's own bundle id, the standard
/// Bonjour service type, an ephemeral port, no extra file roots).
public struct PortholeConfiguration: Sendable {
    public var appName: String
    public var bundleID: String
    /// The Bonjour service type advertised and browsed for.
    public var serviceType: String
    /// nil = let the system pick an ephemeral port.
    public var port: UInt16?
    /// Extra roots exposed by the built-in file connector — App Group container
    /// identifiers the app wants browsable alongside its own sandbox.
    public var appGroupIdentifiers: [String]

    public init(
        appName: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "unknown",
        serviceType: String = "_porthole._tcp",
        port: UInt16? = nil,
        appGroupIdentifiers: [String] = [],
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.serviceType = serviceType
        self.port = port
        self.appGroupIdentifiers = appGroupIdentifiers
    }
}
