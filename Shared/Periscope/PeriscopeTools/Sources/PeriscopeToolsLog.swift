import os

/// Where the tools report *their own* problems: a store read that failed, a
/// stored payload that wouldn't decode.
///
/// Deliberately OSLog rather than Periscope. These surfaces read the log store
/// and refresh on every commit, so emitting into it would commit a change they
/// then reload for — turning one corrupt row into a refresh loop. The tools'
/// failures belong outside the system they inspect, which is the same reason
/// `PeriscopeStore` keeps its own `failureLogger`.
enum PeriscopeToolsLog {
    static let failures = Logger(
        subsystem: "com.stuff.periscope",
        category: "PeriscopeTools",
    )
}
