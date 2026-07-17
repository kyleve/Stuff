import Foundation
import Observation

/// The root of the Ledger model tree. Owns the settings node, the Keychain
/// wrapper (Admin API key), the spend provider (network), and the login-item
/// controller, and exposes a single observable ``LoadState`` the UI renders.
///
/// `configuration` is the *retained backing store* that ``settings`` writes
/// through and persists — the tree never rebuilds it from scratch.
@MainActor
@Observable
public final class LedgerServices {
    /// The spend-load state machine: exactly one of these holds at a time, so
    /// the UI can't see a half-loaded mix of value + error + spinner.
    public enum LoadState: Sendable, Equatable {
        /// Nothing loaded yet (before the first fetch).
        case idle
        /// A fetch is in flight.
        case loading
        /// A fetch succeeded and produced the signed-in member's spend.
        case loaded(MemberSpend)
        /// A fetch failed; carries the reason for the UI to explain.
        case failed(LoadError)
    }

    /// Why a spend fetch couldn't produce a value.
    public enum LoadError: Sendable, Equatable {
        /// No Admin API key or no team-member email is configured yet.
        case missingCredentials
        /// The API responded, but no member matched the configured email.
        case memberNotFound
        /// A non-2xx HTTP response (401 usually means a bad key).
        case http(Int)
        /// The transport failed (offline, DNS, TLS, timeout).
        case network(String)
        /// A 2xx response that didn't decode.
        case decode(String)

        /// A short, user-facing explanation for the popover.
        public var message: String {
            switch self {
                case .missingCredentials:
                    "Add your Admin API key and email in Settings."
                case .memberNotFound:
                    "No team member matches that email. Check it in Settings."
                case .http(401):
                    "That Admin API key was rejected (HTTP 401). Check it in Settings."
                case let .http(status):
                    "The spend request failed (HTTP \(status))."
                case let .network(reason):
                    "Couldn't reach Cursor: \(reason)"
                case let .decode(reason):
                    "Couldn't read the spend response: \(reason)"
            }
        }
    }

    /// The current spend-load state. Observable so the UI reflects it.
    public private(set) var loadState: LoadState = .idle

    /// When the last successful fetch completed, for the "updated …" caption.
    public private(set) var lastUpdated: Date?

    /// Whether an Admin API key is stored. Mirrored from the Keychain so the
    /// UI can reflect it without a (throwing) Keychain read on every access.
    public private(set) var hasAPIKey: Bool = false

    /// Settings; created from the loaded configuration.
    ///
    /// `unowned` is safe: `settings` is reached only through a live
    /// `LedgerServices`, and its callback fires from a direct property write.
    @ObservationIgnored
    public private(set) lazy var settings: LedgerSettings = .init(
        teamMemberEmail: configuration.teamMemberEmail,
        refreshInterval: configuration.refreshInterval,
        onPersistentChange: { [unowned self] in settingsDidChange() },
    )

    /// Whether Ledger is registered to launch at login. Backed by
    /// `SMAppService` (the OS owns the real state). The setter registers or
    /// unregisters and, on failure, logs *and* surfaces ``loginItemError``
    /// while leaving the observed value honest.
    public var startsAtLogin: Bool {
        get { loginItem.isEnabled }
        set {
            do {
                try loginItem.setEnabled(newValue)
                loginItemError = nil
            } catch {
                Self.logger.error("Couldn't update the login item: \(error)")
                loginItemError = newValue
                    ? "Couldn't turn on Launch at login: \(error.localizedDescription)"
                    : "Couldn't turn off Launch at login: \(error.localizedDescription)"
            }
        }
    }

    /// The login item is registered but macOS needs the user to approve it.
    public var loginItemNeedsApproval: Bool {
        loginItem.needsApproval
    }

    /// The most recent login-item failure, surfaced in Settings. Cleared by
    /// the next successful toggle.
    public private(set) var loginItemError: String?

    private static let logger = LedgerLog.channel(.services)

    @ObservationIgnored private var configuration: LedgerConfiguration
    @ObservationIgnored private let configStore: LedgerConfigStore
    @ObservationIgnored private let keychain: any KeychainStore
    @ObservationIgnored private let provider: any SpendProvider
    @ObservationIgnored private let loginItem: LoginItemController
    /// The auto-refresh loop; cancelled by ``stop()``.
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    /// Increments per fetch so a slow earlier response can't clobber a newer
    /// one (manual refresh racing the timer).
    @ObservationIgnored private var requestGeneration = 0

    public convenience init() {
        self.init(
            configStore: .applicationSupport(),
            keychain: SystemKeychainStore(),
            provider: CursorSpendAPI(),
            loginItem: LoginItemController(),
        )
    }

    /// Loads the configuration eagerly so `settings` never sees pre-load
    /// defaults. A file that exists but can't be read keeps the in-memory
    /// defaults without overwriting it — nothing saves until the user changes
    /// something deliberately.
    @_spi(Testing)
    public init(
        configStore: LedgerConfigStore,
        keychain: any KeychainStore,
        provider: any SpendProvider,
        loginItem: LoginItemController,
    ) {
        self.configStore = configStore
        self.keychain = keychain
        self.provider = provider
        self.loginItem = loginItem
        do {
            configuration = try configStore.load()
        } catch {
            Self.logger.error("Couldn't load configuration: \(error)")
            configuration = .initial
        }
        refreshHasAPIKey()
    }

    // MARK: - Lifecycle

    /// Kicks off the first fetch and the periodic refresh loop. Call once at
    /// app launch.
    public func start() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.settings.refreshInterval, interval > 0 else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Cancels the periodic refresh loop (the app's quit path).
    public func stop() {
        refreshLoop?.cancel()
        refreshLoop = nil
    }

    // MARK: - Spend

    /// Fetches the current-cycle spend and reduces it to the configured
    /// member. Updates ``loadState`` (and ``lastUpdated`` on success). Safe to
    /// call concurrently: a stale response is dropped.
    public func refresh() async {
        guard let email = settings.teamMemberEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty
        else {
            loadState = .failed(.missingCredentials)
            return
        }
        let key: String?
        do {
            key = try keychain.read()
        } catch {
            Self.logger.error("Couldn't read the API key: \(error.localizedDescription)")
            key = nil
        }
        guard let apiKey = key, !apiKey.isEmpty else {
            loadState = .failed(.missingCredentials)
            return
        }

        requestGeneration += 1
        let generation = requestGeneration
        loadState = .loading

        do {
            let response = try await provider.fetchSpend(apiKey: apiKey)
            guard generation == requestGeneration else { return }
            if let member = response.member(matching: email) {
                loadState = .loaded(member)
                lastUpdated = Date()
            } else {
                loadState = .failed(.memberNotFound)
            }
        } catch let error as SpendProviderError {
            guard generation == requestGeneration else { return }
            loadState = .failed(error.asLoadError)
        } catch {
            guard generation == requestGeneration else { return }
            Self.logger.error("Unexpected spend error: \(error.localizedDescription)")
            loadState = .failed(.network(error.localizedDescription))
        }
    }

    // MARK: - Credentials

    /// Stores (or, for an empty string, clears) the Admin API key in the
    /// Keychain and refreshes spend. Rethrows a Keychain failure so the UI can
    /// surface it rather than silently losing the key.
    public func setAPIKey(_ key: String) throws {
        try keychain.write(key)
        refreshHasAPIKey()
    }

    /// Removes the stored Admin API key.
    public func clearAPIKey() throws {
        try keychain.remove()
        refreshHasAPIKey()
    }

    private func refreshHasAPIKey() {
        do {
            let key = try keychain.read()
            hasAPIKey = !(key ?? "").isEmpty
        } catch {
            Self.logger.error("Couldn't read the API key: \(error.localizedDescription)")
            hasAPIKey = false
        }
    }

    // MARK: - Login item

    /// Re-reads the login-item status from the OS; it can change outside the
    /// app (System Settings › General › Login Items).
    public func refreshLoginItemStatus() {
        loginItem.refresh()
    }

    /// Opens System Settings › General › Login Items so the user can approve a
    /// pending login item.
    public func openSystemSettingsLoginItems() {
        loginItem.openSystemSettingsLoginItems()
    }

    // MARK: - Persistence

    private func settingsDidChange() {
        configuration.teamMemberEmail = settings.teamMemberEmail
        configuration.refreshInterval = settings.refreshInterval
        persist()
    }

    private func persist() {
        do {
            try configStore.save(configuration)
        } catch {
            Self.logger.error("Couldn't save configuration: \(error)")
        }
    }
}

extension SpendProviderError {
    /// Maps the transport-level error into the user-facing ``LedgerServices/LoadError``.
    fileprivate var asLoadError: LedgerServices.LoadError {
        switch self {
            case let .http(status): .http(status)
            case let .network(reason): .network(reason)
            case let .decode(reason): .decode(reason)
        }
    }
}
