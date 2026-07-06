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

    /// The local control socket the `foreman-mcp` server talks to. Started
    /// after launch, torn down on quit. `nil` until started (and if binding
    /// fails, so a socket problem never blocks the app).
    @ObservationIgnored private var controlServer: ControlServer?

    /// The discovered repositories, sorted by name — the observable source
    /// of truth the sidebar and detail bind to.
    var repos: [Repo] {
        services.repos
    }

    /// The discovered repos grouped for the sidebar: enabled on top, disabled
    /// below, favorites floated to the top of each section.
    var repoSections: [RepoSection] {
        services.repoSections
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
    /// surfaces any failure on `loginItemError`).
    var startsAtLogin: Bool {
        get { services.startsAtLogin }
        set { services.startsAtLogin = newValue }
    }

    /// The login item is registered but awaiting approval in System Settings.
    var loginItemNeedsApproval: Bool {
        services.loginItemNeedsApproval
    }

    /// The most recent login-item failure (shown in the General settings pane).
    var loginItemError: String? {
        services.loginItemError
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

    /// Starts listening on the MCP control socket. Called once after launch.
    func startControlServer() {
        guard controlServer == nil else { return }
        let server = ControlServer(
            socketURL: ForemanServices.controlSocketURL,
            handler: ControlRequestHandler(services: services),
        )
        server.start()
        controlServer = server
    }

    /// Stops the control socket and removes its file; part of the quit path.
    func stopControlServer() {
        controlServer?.stop()
        controlServer = nil
    }

    /// Removes the copy at `repo` (stops its worker, then git-removes a
    /// worktree or trashes a clone). UI intent for the Remove-copy action;
    /// surfaces any failure on ``actionError`` rather than throwing into the
    /// view.
    func removeCopy(_ repo: Repo) async {
        do {
            try await services.removeCopy(at: repo.rootURL)
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The most recent failure from a user-triggered action (currently
    /// Remove-copy). Shown as an alert; cleared when dismissed.
    private(set) var actionError: String?

    /// Two-way binding for the action-error alert: reading tells the alert
    /// whether to show, setting it `false` (dismiss) clears the message. Keeps
    /// ``actionError`` the single source of truth rather than a view-owned
    /// mirror.
    var isShowingActionError: Bool {
        get { actionError != nil }
        set { if !newValue { actionError = nil } }
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

    /// Opens System Settings › General › Login Items (to approve a pending
    /// login item).
    func openSystemSettingsLoginItems() {
        services.openSystemSettingsLoginItems()
    }
}
