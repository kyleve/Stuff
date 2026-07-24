import os

/// PortholeKit's own lightweight logging, deliberately independent of Periscope:
/// the device runtime must not depend on the logging stack it can *expose* as a
/// connector. Failures (bad frames, handshake errors, dropped events) log here
/// rather than being swallowed.
enum PortholeLog {
    static let runtime = Logger(subsystem: "com.stuff.porthole", category: "runtime")
    static let session = Logger(subsystem: "com.stuff.porthole", category: "session")
    static let network = Logger(subsystem: "com.stuff.porthole", category: "network")
}
