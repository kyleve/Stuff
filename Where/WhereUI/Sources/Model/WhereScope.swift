import Foundation
import Observation
import PeriscopeCore
import RegionKit
import WhereCore

/// Everything the app is logged in *to*: the service layer over one open
/// store, the preferences whose intent that layer is driven by, and the
/// durable log store the two record into.
///
/// A scope is created whole and never reconfigured — the store it carries is
/// opened once, and changing what the app is logged in to means activating a
/// *different* scope rather than reassigning fields on this one. `WhereModel`
/// owns which scope is active; `WhereSession` is built from one, so every
/// logged-in surface reads the store and the preferences of the same scope
/// and the two can't drift apart.
///
/// The split it draws is app-scope versus logged-in scope: `WhereModel` lives
/// for the process (it exists before any store is open, and outlives a reset),
/// while everything here belongs to one logged-in world. Nothing here exists
/// until the user has one — see ``WhereModel/resolveScope()``.
///
/// The log store is the one member that lands late: opening it touches disk,
/// so a real scope kicks that off and adopts the store when it's ready rather
/// than making every logged-in surface wait. Until then this scope's records
/// reach OSLog only, as they do for the whole pre-scope window.
@MainActor
@Observable
public final class WhereScope {
    /// The service layer — the entry point to the domain for every logged-in
    /// surface. Owns this scope's store.
    ///
    /// Public because a scope *is* the composition value the app hands around:
    /// the launch builds sessions from it, and the app target derives the App
    /// Intents stack from the same services. Views still reach the domain
    /// through their view models, not through here.
    public let services: WhereServices

    /// The persisted user intent (onboarding, tracking, reminder/summary
    /// schedules) this scope reads and writes. A reference, shared with
    /// whoever else holds these preferences, so a write from onboarding and a
    /// read from the session see one store.
    public let preferences: WherePreferences

    /// Where this scope's records are going.
    ///
    /// One value rather than a store beside a token beside a flag, because the
    /// interesting state isn't "do we have a store" — it's whether this scope
    /// *should* be receiving records at all. A store that finishes opening
    /// while the scope is set aside must be remembered without being attached,
    /// which two independent optionals can't express: the version that did
    /// silently routed a shadowed scope's records to disk.
    private enum LogRouting {
        /// No store yet. One may still be opening, and when it arrives this
        /// scope will route into it.
        case pending
        /// Routing into `store`, registered on the logging system as `token`.
        case routing(store: PeriscopeStore, token: Periscope.SinkToken)
        /// Deliberately not routing — another scope is active, or this is a
        /// preview that only wants something to browse. Carries the store once
        /// one has opened, so routing can resume without reopening; `nil` when
        /// the open hadn't landed yet, which is what tells that open to record
        /// its store instead of attaching it.
        case idle(store: PeriscopeStore?)
    }

    private var logRouting: LogRouting = .pending

    /// The durable log store this scope's records persist to, once it has
    /// opened. Observable because the DEBUG developer surface renders off its
    /// arrival. Nil in previews and tests, which log through the in-memory
    /// pipeline only.
    public var logStore: PeriscopeStore? {
        switch logRouting {
            case .pending: nil
            case let .routing(store, _): store
            case let .idle(store): store
        }
    }

    /// The logging system this scope's sink is registered on — injected rather
    /// than reached for, so a test can assert exactly which world's records
    /// reach which store without touching the process-wide pipeline. The app
    /// passes `Periscope.shared` at its composition root.
    @ObservationIgnored private let logSystem: Periscope

    private static let logger = WhereLog.root(WhereLaunchLog.self)

    /// How much log history the durable store keeps: 100 days. Older events
    /// are pruned when the store opens so the database can't grow without
    /// bound. (A size cap to bound heavy-logging devices within the window is
    /// tracked in `Where/TODOs.md`.)
    private static let logRetention: TimeInterval = 100 * 24 * 60 * 60

    /// Whether this scope is the user's real world or a throwaway demo one.
    ///
    /// Carried on the scope rather than derived at each call site because it
    /// changes what a *session* may do — a demo session must not write to the
    /// Spotlight index or the widget's shared file, which outlive it — and the
    /// session is built from the scope.
    let kind: Kind

    /// Which world a scope represents.
    enum Kind {
        /// The user's real, persisted world.
        case real
        /// A demo world: in memory, discarded on exit, and never allowed to
        /// leave a mark on the device.
        case demo
    }

    /// Build a scope over an already-assembled service layer, with no durable
    /// log store. The app builds its real scope with
    /// ``real(bootstrap:preferences:logSystem:)``; this is the seam previews and
    /// tests inject one through.
    public convenience init(
        services: WhereServices,
        preferences: WherePreferences,
        logSystem: Periscope,
    ) {
        self.init(
            kind: .real,
            services: services,
            preferences: preferences,
            logSystem: logSystem,
        )
    }

    init(
        kind: Kind,
        services: WhereServices,
        preferences: WherePreferences,
        logSystem: Periscope,
    ) {
        self.kind = kind
        self.services = services
        self.preferences = preferences
        self.logSystem = logSystem
    }

    /// The user's real, persisted world: the app's **one** on-disk store (see
    /// `WhereBootstrap.makeServices`), the persisted preferences, and the
    /// durable log store — which opens on its own task, so a slow open or a
    /// lightweight migration never delays the launch that awaits this.
    ///
    /// Throws if the store can't be opened, so the caller can surface it: for
    /// the launch that's a failed drive, for onboarding a failed gate.
    static func real(
        bootstrap: any WhereScopeAssembling,
        preferences: WherePreferences,
        logSystem: Periscope,
    ) async throws -> WhereScope {
        let scope = try await WhereScope(
            kind: .real,
            services: bootstrap.makeServices(),
            preferences: preferences,
            logSystem: logSystem,
        )
        scope.openDurableLogStore(from: bootstrap)
        return scope
    }

    /// A throwaway world to demonstrate the app in: an in-memory store seeded
    /// with a plausible year, in-memory preferences, and an in-memory log
    /// store — nothing here survives the process, and nothing it does reaches
    /// the user's data.
    ///
    /// Every collaborator that would touch the device outside the store is a
    /// no-op: the schedulers never ask for notification permission, the widget
    /// refresher never writes the shared snapshot file, and the location
    /// source is scripted, so demo mode prompts for nothing. The scripted
    /// source reports `.always` and answers a one-shot fix from New York, so
    /// the app behaves as it would for a user who has granted everything.
    ///
    /// Building this is the slow part of entering demo mode (seeding a year),
    /// which is why the entry point shows an interstitial while it runs.
    ///
    /// Reached through ``WhereModel/makeDemoScope()``, which supplies the clock
    /// and logging system it was composed with.
    static func demo(
        now: @escaping @Sendable () -> Date,
        logSystem: Periscope,
    ) async throws -> WhereScope {
        let aggregator = DayAggregator()
        let locationSource = ScriptedLocationSource(authorizationStatus: .always)
        locationSource.setNextRequestedLocation(LocationSample(
            timestamp: now(),
            coordinate: DemoDataBuilder.homeCoordinate,
            horizontalAccuracy: 12,
            source: .gpsVisit,
        ))
        let services = try await WhereServices.make(
            store: SwiftDataStore.inMemory(),
            locationSource: locationSource,
            aggregator: aggregator,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
            locationOutbox: NoOpLocationOutbox(),
            now: now,
        )
        try await DemoDataBuilder(now: now(), calendar: aggregator.calendar)
            .seed(into: services)

        let preferences = WherePreferences(store: InMemoryKeyValueStore())
        // Onboarded and tracking, so the demo opens on the logged-in app with
        // live tracking shown rather than on a first-run prompt. These are the
        // demo's own preferences: the user's real ones are untouched, which is
        // what makes quitting mid-demo return to onboarding.
        preferences.hasOnboarded = true
        preferences.wantsTracking = true

        let scope = WhereScope(
            kind: .demo,
            services: services,
            preferences: preferences,
            logSystem: logSystem,
        )
        try await scope.attachLogSink(PeriscopeStore.make(
            storage: .inMemory,
            session: .current(),
        ))
        return scope
    }

    /// Record `store` as the log store this scope's developer surface browses,
    /// without routing anything into it. For previews and tests, which want the
    /// viewer populated but must not leave a sink attached to the logging
    /// system behind them.
    func attach(logStore store: PeriscopeStore) {
        logRouting = .idle(store: store)
    }

    /// Route the logging system into `store` and record it as this scope's
    /// durable log store, so everything logged while this scope is active
    /// persists there.
    ///
    /// A store arriving while the scope is `idle` is *remembered, not
    /// attached*: the open was started when this scope was active, but another
    /// world has become active since, and routing into a shadowed scope is
    /// exactly the leak this state machine exists to prevent.
    func attachLogSink(_ store: PeriscopeStore) {
        switch logRouting {
            case .pending:
                logRouting = .routing(store: store, token: logSystem.add(sink: store))
            case .routing:
                break
            case .idle:
                logRouting = .idle(store: store)
        }
    }

    /// Stop routing into this scope's log store. Awaits the sink settling (it
    /// receives everything already emitted, then nothing), so a scope that is
    /// no longer active can't keep persisting another scope's records. The
    /// store itself is retained, so a scope that becomes active again can pick
    /// its sink back up — and a store still opening is pre-emptively barred
    /// from attaching when it lands.
    ///
    /// Public because whoever owns a scope has to be able to settle one it is
    /// done with — `WhereModel` on the way in and out of demo mode, and a test
    /// that builds a scope directly, which must leave no sink behind.
    public func detachLogSink() async {
        switch logRouting {
            case .pending:
                logRouting = .idle(store: nil)
            case let .routing(store, token):
                logRouting = .idle(store: store)
                await logSystem.remove(token)
            case .idle:
                break
        }
    }

    /// Route back into the log store this scope already opened — the other half
    /// of `detachLogSink()`, for a scope that was set aside while another world
    /// was active. A scope whose store never arrived returns to `pending`, so
    /// the open still in flight attaches it as it originally would have.
    func reattachLogSink() {
        guard case let .idle(store) = logRouting else { return }
        if let store {
            logRouting = .routing(store: store, token: logSystem.add(sink: store))
        } else {
            logRouting = .pending
        }
    }

    /// Open the durable log store and attach it as this scope's sink, off the
    /// critical path — it touches disk (and may run a lightweight migration),
    /// which must not delay the launch. The OSLog sink covers the window
    /// before it lands. (Fully closing that window — a bootstrap journal from
    /// process start — is tracked as a P0 in `Shared/Periscope/TODOs.md`.)
    ///
    /// Degraded-but-handled on failure: if the store can't open, logging keeps
    /// flowing through OSLog and the failure is recorded (with the error
    /// attached) rather than taking a launch down over diagnostics. An
    /// assembly with no durable store (previews, tests) simply gets none.
    private func openDurableLogStore(from bootstrap: any WhereScopeAssembling) {
        Task {
            let store: PeriscopeStore?
            do {
                store = try await bootstrap.makeLogStore()
            } catch {
                Self.logger(attachments: [.error(error, name: "open-error")]) {
                    .loggingStoreUnavailable(description: String(describing: error))
                }
                return
            }
            guard let store else { return }
            attachLogSink(store)
            Self.logger { .loggingStoreReady }
            pruneHistory(in: store)
        }
    }

    /// Trim log history past `logRetention` on its own task, so it never
    /// delays `.loggingStoreReady`. The prune runs on the store actor (off the
    /// main thread); a failure is degraded-but-handled — the store keeps its
    /// last good history and stays usable, it just isn't trimmed this launch.
    private func pruneHistory(in store: PeriscopeStore) {
        Task {
            do {
                let cutoff = Date().addingTimeInterval(-Self.logRetention)
                let pruned = try await store.pruneEvents(olderThan: cutoff)
                Self.logger { .historyPruned(prunedEventCount: pruned) }
            } catch {
                Self.logger(attachments: [.error(error, name: "prune-error")]) {
                    .historyPruneFailed(description: String(describing: error))
                }
            }
        }
    }
}
