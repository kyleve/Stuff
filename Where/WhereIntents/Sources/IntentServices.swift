import WhereCore

/// A process-wide cache of the intent layer's `WhereServices`.
///
/// Every App Intent resolves its services through `current()` rather than
/// assembling a fresh stack per invocation. Two reasons:
///
/// - **Cost:** assembling the stack derives its attribution from the store's
///   tracked regions; redoing that on every query, action, and snippet reload
///   is wasteful.
/// - **Consistency:** a snippet's "Log today here" button (`LogDayIntent`) and
///   the subsequent snippet reload (`DaysInRegionSnippetIntent`) run in the same
///   process. Sharing one stack makes the write immediately visible on reload.
///
/// The stack itself is **injected by the app's composition root**: after the
/// launch assembles its services, the app derives a store-sharing intents
/// stack from them (`WhereServices.forIntents(sharingStoreOf:)`) and hands it
/// to `install(_:)` — so intents run over the same store instance the app
/// opened, an intent write pings the same `changes()` signal the running UI
/// refreshes from, and no second container is opened over the app's store
/// file. Only an intent that fires *before* the launch installs the stack
/// (e.g. a Siri invocation racing app startup) self-assembles the fallback
/// `WhereServices.forIntents()`.
public actor IntentServices {
    public static let shared = IntentServices()

    private var cached: WhereServices?

    init() {}

    /// Install the store-sharing stack the app's composition root derived from
    /// its own services. Replaces any fallback stack an early intent may have
    /// self-assembled, so later intents ride the app's store instance.
    public func install(_ services: WhereServices) {
        cached = services
    }

    func current() async throws -> WhereServices {
        if let cached {
            return cached
        }
        let services = try await WhereServices.forIntents()
        cached = services
        return services
    }
}
