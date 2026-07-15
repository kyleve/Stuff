import WhereCore

/// A process-wide cache of the intent layer's `WhereServices`.
///
/// Every App Intent resolves its services through `current()` rather than
/// opening a fresh store per invocation. Two reasons:
///
/// - **Cost:** `WhereServices.forIntents()` cold-opens the App Group SwiftData
///   store; doing that on every query, action, and snippet reload is wasteful.
/// - **Consistency:** a snippet's "Log today here" button (`LogDayIntent`) and
///   the subsequent snippet reload (`DaysInRegionSnippetIntent`) run in the same
///   process. Sharing one store instance makes the write immediately visible on
///   reload, so the count updates in place instead of racing cross-coordinator
///   remote-change propagation.
///
/// The store is opened lazily on first use and kept for the process lifetime,
/// mirroring how the running app holds its own store.
actor IntentServices {
    static let shared = IntentServices()

    private var cached: WhereServices?

    func current() throws -> WhereServices {
        if let cached {
            return cached
        }
        let services = try WhereServices.forIntents()
        cached = services
        return services
    }
}
