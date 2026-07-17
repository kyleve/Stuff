import WhereCore

/// A process-wide cache of the intent layer's `WhereServices`.
///
/// Every App Intent resolves its services through `current()` rather than
/// assembling a fresh stack per invocation. Two reasons:
///
/// - **Cost:** `WhereServices.forIntents()` derives its attribution from the
///   store's tracked regions; re-assembling that on every query, action, and
///   snippet reload is wasteful.
/// - **Consistency:** a snippet's "Log today here" button (`LogDayIntent`) and
///   the subsequent snippet reload (`DaysInRegionSnippetIntent`) run in the same
///   process. Sharing one stack makes the write immediately visible on reload.
///
/// The backing store is the process's *canonical* `SwiftDataStore` — the same
/// instance the app's launch opened (see `WhereServices.forIntents()`) — so an
/// intent write pings the same `changes()` signal the running UI refreshes
/// from, and no second container is ever opened over the app's store file.
actor IntentServices {
    static let shared = IntentServices()

    private var cached: WhereServices?

    func current() async throws -> WhereServices {
        if let cached {
            return cached
        }
        let services = try await WhereServices.forIntents()
        cached = services
        return services
    }
}
