import Foundation
import Observation
import PortholeRemote
import PortholeRuntime
import PortholeUI
import WhereCore

/// App-owned debugger wiring. Activation attaches existing resources and never constructs a Where
/// store.
@MainActor
@Observable
public final class WherePortholeController {
    public let registry: PortholeRegistry
    public let presentation: PortholePresentationController
    public private(set) var remoteHost: PortholeHostPresentationModel?
    public private(set) var state: State = .disabled
    public enum State {
        case disabled
        case preparing
        case ready(PortholeScopeToken)
        case failed(String)
    }

    public var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            preferences.isPortholeEnabled = isEnabled
        }
    }

    public typealias ModuleInstaller = @Sendable (
        PortholeRegistry,
        PortholeScopeToken
    ) async throws -> Void
    @ObservationIgnored private var moduleInstallers: [ModuleInstaller] = []
    public func addModuleInstaller(_ installer: @escaping ModuleInstaller) {
        moduleInstallers.append(installer)
    }

    @ObservationIgnored private let preferences: WherePreferences
    @ObservationIgnored private let investigationURL: URL
    @ObservationIgnored private let screenshotEvidence: PortholeScreenshotEvidence
    @ObservationIgnored private var attachedScope: ObjectIdentifier?
    @ObservationIgnored private var currentToken: PortholeScopeToken?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private let applicationID = UUID()
    @ObservationIgnored private var screens: [Screen] = []
    @ObservationIgnored private var frozenOrigin: CapturedOrigin?
    private enum CapturedOrigin {
        case application
        case screen(CapturedScreen)
    }

    private struct CapturedScreen {
        let screen: Screen
        let values: PortholeValue
        let capturedAt: Date
    }

    struct Screen {
        let id: UUID
        let owningScope: ObjectIdentifier?
        let depth: Int
        let title: String
        let source: PortholeSourceLocation
        let capture: @MainActor () throws -> PortholeValue
        let roots: [any Sendable]
    }

    public convenience init(preferences: WherePreferences) {
        let directory = URL.applicationSupportDirectory.appending(
            path: "Porthole",
            directoryHint: .isDirectory,
        )
        self.init(
            preferences: preferences,
            registry: PortholeRegistry(
                journal: PortholeOperationJournal(url: directory
                    .appending(path: "operations.json")),
                objectLimit: 10000,
            ),
            investigationURL: directory.appending(path: "investigation.json"),
            screenshots: PortholeWindowScreenshotCapture(),
        )
    }

    @_spi(Testing)
    public init(
        preferences: WherePreferences,
        registry: PortholeRegistry,
        investigationURL: URL,
        screenshots: any PortholeScreenshotCapturing,
    ) {
        self.preferences = preferences
        self.registry = registry
        self.investigationURL = investigationURL
        isEnabled = preferences.isPortholeEnabled
        let presentation = PortholePresentationController(
            registry: registry,
            applicationTitle: "Where",
        )
        self.presentation = presentation
        screenshotEvidence = PortholeScreenshotEvidence(source: screenshots) {
            presentation.isPresented
        }
    }

    /// Called at the root whenever activation or the owning Where scope changes.
    public func reconcile(scope: WhereScope?) async {
        let identity = scope.map(ObjectIdentifier.init)
        if isEnabled, case .ready = state, attachedScope == identity { return }
        let revision = UUID()
        self.revision = revision
        let previousHost = remoteHost
        let previousToken = currentToken
        remoteHost = nil
        currentToken = nil
        attachedScope = identity
        frozenOrigin = nil
        screenshotEvidence.reset()
        presentation.dismiss()
        state = isEnabled ? .preparing : .disabled
        await previousHost?.disable()
        if let previousToken { await registry.invalidate(previousToken) }
        guard self.revision == revision, !Task.isCancelled else { return }
        await registry.setEnabled(isEnabled)
        guard self.revision == revision, !Task.isCancelled else { return }
        guard isEnabled else { state = .disabled; return }
        var installingToken: PortholeScopeToken?
        do {
            let token = await registry.createScope(id: .init(rawValue: "where.application"))
            installingToken = token
            guard self.revision == revision,
                  !Task.isCancelled else { await registry.invalidate(token); return }
            currentToken = token
            try await WherePortholeBindings.install(in: registry, scope: token)
            for installer in moduleInstallers {
                try await installer(registry, token)
            }
            try await PortholeBuiltinCapabilities.install(in: registry, scope: token)
            try await WherePortholeSystemCapabilities.install(
                scope: scope,
                registry: registry,
                token: token,
                screenshot: { [weak self] in
                    guard let self, currentToken == token,
                          isEnabled else { throw PortholeError.staleScope }
                    return try screenshotEvidence.png()
                },
            )
            try await PortholeFiles(roots: [
                .init(
                    name: .init(rawValue: "Documents"),
                    url: .documentsDirectory,
                    excludedPaths: [],
                ),
            ], maximumBytes: 1_048_576).install(in: registry, scope: token)
            if let scope {
                try await WherePortholeCapabilities.install(
                    scope: scope,
                    registry: registry,
                    token: token,
                )
            }
            try Task.checkCancellation()
            guard self.revision == revision,
                  isEnabled else { await registry.invalidate(token); return }
            let applicationID = applicationID
            let host = PortholeHostPresentationModel(
                executor: registry,
                application: {
                    PortholeRemoteApplication(
                        applicationID: applicationID,
                        name: "Where",
                        scopes: [token],
                    )
                },
                serviceName: "Where Porthole",
                keychainService: "\(Bundle.main.bundleIdentifier ?? "com.stuff.where").porthole.remote",
            )
            remoteHost = host
            presentation.attachHost(model: host)
            state = .ready(token)
        } catch {
            if let installingToken { await registry.invalidate(installingToken) }
            guard self.revision == revision else { return }
            currentToken = nil
            WherePortholeLog.logger { .failed(.activation) }
            state = .failed(error.localizedDescription)
        }
    }

    func enter(_ screen: Screen) {
        screens.removeAll { $0.id == screen.id }
        screens.append(screen)
    }

    func leave(_ id: UUID) {
        screens.removeAll { $0.id == id }
    }

    /// Freeze before developer chrome appears. Developer destinations do not register origins.
    func captureMenuOrigin() {
        guard !presentation.isPresented else { return }
        guard isEnabled, case .ready = state else { frozenOrigin = nil; return }
        frozenOrigin = nil
        do {
            let visible = screens.filter { $0.owningScope == attachedScope }
            let depth = visible.map(\.depth).max()
            if let screen = visible.last(where: { $0.depth == depth }) {
                frozenOrigin = try .screen(CapturedScreen(
                    screen: screen,
                    values: screen.capture(),
                    capturedAt: Date(),
                ))
            } else { frozenOrigin = .application }
            do { try screenshotEvidence.freeze() }
            catch { WherePortholeLog.logger { .failed(.screenshot) } }
        } catch {
            WherePortholeLog.logger { .failed(.capture) }
            state = .failed(error.localizedDescription)
        }
    }

    public func invalidateScope() async {
        let revision = UUID()
        self.revision = revision
        let previousHost = remoteHost
        let previousToken = currentToken
        remoteHost = nil
        currentToken = nil
        attachedScope = nil
        frozenOrigin = nil
        screenshotEvidence.reset()
        screens.removeAll()
        presentation.dismiss()
        state = isEnabled ? .preparing : .disabled
        await previousHost?.disable()
        if let previousToken { await registry.invalidate(previousToken) }
    }

    func presentCurrentScreen() async {
        guard case let .ready(token) = state else { return }
        if frozenOrigin == nil { captureMenuOrigin() }
        guard let frozenOrigin, case .ready = state else { return }
        let captured: CapturedScreen
        switch frozenOrigin {
            case .application:
                presentation.present(origin: .application(token))
                guard await configureGitHub(scope: token) else { return }
                configureAgent(context: nil)
                return
            case let .screen(screen): captured = screen
        }
        do {
            let screen = captured.screen
            let values = captured.values
            var references: [PortholeObjectReference] = []
            for root in screen
                .roots
            {
                try await references.append(registry.retain(root, in: token, retention: .bounded(
                    pool: .init(rawValue: "where.screen-roots"),
                    maximumCount: 64,
                )))
            }
            let context = PortholeContext(
                id: .init(rawValue: UUID().uuidString),
                title: screen.title,
                scope: token,
                capturedAt: captured.capturedAt,
                values: values,
                objects: references,
                links: attachedScope == nil ? [] : [
                    .init(
                        id: .init(rawValue: "where.services"),
                        label: "Where services",
                        relation: "Runs in this application scope",
                    ),
                ],
                source: screen.source,
            )
            try await registry.capture(context)
            guard currentToken == token, isEnabled else { return }
            presentation.registerContexts([context])
            presentation.present(origin: .screen(context))
            guard await configureGitHub(scope: token) else { return }
            configureAgent(context: context)
        } catch {
            guard currentToken == token else { return }
            WherePortholeLog.logger { .failed(.presentation) }
            state = .failed(error.localizedDescription)
        }
    }

    private func configureAgent(context: PortholeContext?) {
        do {
            try presentation.configureAgent(
                storageURL: investigationURL,
                keychainService: "\(Bundle.main.bundleIdentifier ?? "com.stuff.where").porthole.models",
                context: context,
            )
        } catch {
            WherePortholeLog.logger { .failed(.agent) }
        }
    }

    private func configureGitHub(scope: PortholeScopeToken) async -> Bool {
        let session = presentation.sessionID
        do {
            let bundle = Bundle.main
            let commit = bundle.object(forInfoDictionaryKey: "WhereGitSHA") as? String ?? "unknown"
            let status = bundle.object(forInfoDictionaryKey: "WhereGitStatus") as? String ?? "unknown"
            let configuration = bundle
                .object(forInfoDictionaryKey: "WhereConfiguration") as? String ?? "unknown"
            try await presentation.configureGitHub(
                storageURL: investigationURL.deletingLastPathComponent()
                    .appending(path: "github-workspace.json"),
                keychainService: "\(bundle.bundleIdentifier ?? "com.stuff.where").porthole.github",
                clientID: bundle
                    .object(forInfoDictionaryKey: "PortholeGitHubClientID") as? String ?? "",
                installedBuildIdentity: "\(commit) (\(configuration), \(status))",
                isDirty: status != "clean",
                initialRepository: .init(owner: "kyleve", name: "Stuff"),
                initialBranch: "main",
            )
        } catch {
            guard currentToken == scope, presentation.sessionID == session else { return false }
            WherePortholeLog.logger { .failed(.github) }
        }
        return currentToken == scope && presentation.sessionID == session && presentation
            .isPresented && isEnabled
    }
}
