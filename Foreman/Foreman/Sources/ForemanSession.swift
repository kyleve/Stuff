import ForemanCore
import Foundation
import Observation

/// Thin app-side facade over the ForemanCore model tree. Views read the
/// ``Repo`` objects (and bind their observable state) straight from Core;
/// this class just owns the ``ForemanServices`` root and forwards the few
/// app-level intents (launch, rescan, quit teardown).
@MainActor
@Observable
final class ForemanSession {
    let services: ForemanServices

    /// The discovered repositories, sorted by name — the observable source
    /// of truth the sidebar and detail bind to.
    var repos: [Repo] {
        services.repos
    }

    /// Global settings; `SettingsView` writes through these observable
    /// properties (persistence and rescans happen in Core).
    var settings: AppSettings {
        services.settings
    }

    /// The most recent user-visible problem (config unreadable, scan failed,
    /// save failed). Per-repo failures surface on each repo's worker.
    var issueMessage: String? {
        services.issueMessage
    }

    var isInhibitingSleep: Bool {
        services.isInhibitingSleep
    }

    var isAnyWorkerLive: Bool {
        services.isAnyWorkerLive
    }

    /// Whether Foreman launches at login. `SettingsView` binds this two-way;
    /// the setter registers/unregisters the login item in Core (which logs and
    /// surfaces any failure on `issueMessage`).
    var startsAtLogin: Bool {
        get { services.startsAtLogin }
        set { services.startsAtLogin = newValue }
    }

    init(services: ForemanServices) {
        self.services = services
    }

    convenience init() {
        self.init(services: ForemanServices(
            configStore: .applicationSupport(),
            logDirectory: ForemanServices.defaultLogDirectory,
        ))
    }

    /// First scan and launch restore. Called once at app launch.
    func start() {
        services.start()
    }

    /// Stops every worker; the app's quit path.
    func stopAllWorkers() {
        services.stopAll()
    }

    /// Re-lists the scan directory, preserving live workers for repos that
    /// remain.
    func rescan() {
        services.rescan()
    }

    /// Re-reads the login-item status from the OS (it can change in System
    /// Settings while Foreman runs).
    func refreshLoginItemStatus() {
        services.refreshLoginItemStatus()
    }
}
