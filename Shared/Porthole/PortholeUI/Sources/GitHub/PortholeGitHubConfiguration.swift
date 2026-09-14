import Foundation
import PortholeGitHub
import PortholeRuntime

/// Owns one client and workspace for the controller, even when its presentation or scope changes.
@MainActor
final class PortholeGitHubConfiguration {
    struct Identity: Equatable {
        let storageURL: URL
        let keychainService: String
        let clientID: String
        let installedBuildIdentity: String
        let isDirty: Bool
    }

    let identity: Identity
    let client: GitHubConfigurableClient
    let store: GitHubWorkspaceStore
    let source: GitHubInstalledSource
    let model: PortholeGitHubPresentationModel
    private var registeredScopes: Set<PortholeScopeToken> = []
    private var registrations: [PortholeScopeToken: Task<Void, any Error>] = [:]

    init(
        identity: Identity,
        source: GitHubInstalledSource,
        initialRepository: GitHubRepository,
        initialBranch: String,
        initialPaths: [GitHubRepositoryPath],
    ) throws {
        self.identity = identity
        self.source = source
        client = try GitHubConfigurableClient(
            clientID: identity.clientID.isEmpty ? nil : GitHubClientID(identity.clientID),
            configurationURL: identity.storageURL.deletingLastPathComponent()
                .appending(path: "github-client-id.json"),
            transport: GitHubURLSessionTransport(session: URLSession(configuration: .ephemeral)),
            credentials: GitHubKeychainCredentialStore(service: identity.keychainService),
        )
        store = try GitHubWorkspaceStore(storageURL: identity.storageURL)
        model = PortholeGitHubPresentationModel(
            authentication: client,
            repository: client,
            publisher: client,
            workspaceStore: store,
            installedSource: source,
            initialRepository: initialRepository,
            initialBranch: initialBranch,
            initialPaths: initialPaths,
        )
    }

    func bind(registry: PortholeRegistry, scope: PortholeScopeToken) async throws {
        if registeredScopes.contains(scope) { return }
        if let task = registrations[scope] { try await task.value; return }
        let task = Task {
            try await PortholeGitHubWorkspaceCapabilities.install(
                store: store,
                client: client,
                installedSource: source,
                registry: registry,
                scope: scope,
            )
        }
        registrations[scope] = task
        defer { registrations[scope] = nil }
        try await task.value
        registeredScopes.insert(scope)
    }
}

extension PortholePresentationController {
    /// Call after presenting the captured origin. Repeated calls retain one workspace and register
    /// each scope once. Only scratch-workspace capabilities enter the shared executor.
    public func configureGitHub(
        storageURL: URL,
        keychainService: String,
        clientID: String,
        installedBuildIdentity: String,
        isDirty: Bool,
        initialRepository: GitHubRepository,
        initialBranch: String,
    ) async throws {
        guard let session = sessionID,
              let scope = origin?.scope else { throw PortholeError.staleScope }
        do {
            let identity = PortholeGitHubConfiguration.Identity(
                storageURL: storageURL.standardizedFileURL,
                keychainService: keychainService,
                clientID: clientID,
                installedBuildIdentity: installedBuildIdentity,
                isDirty: isDirty,
            )
            let configuration: PortholeGitHubConfiguration
            if let existing = githubConfiguration {
                guard existing.identity == identity else {
                    throw PortholeError
                        .unsupported(
                            "This controller already owns a different GitHub workspace configuration.",
                        )
                }
                configuration = existing
            } else {
                let files = try await registry.sourceFiles(in: scope)
                guard sessionID == session,
                      origin?.scope == scope else { throw PortholeError.staleScope }
                guard files.allSatisfy(\.hasValidHash) else {
                    throw PortholeError.unsupported("Installed source failed its integrity check.")
                }
                // A second call can finish reading source during the same suspension.
                if let existing = githubConfiguration {
                    guard existing.identity == identity else { throw PortholeError.staleScope }
                    configuration = existing
                } else {
                    let source = try GitHubInstalledSource(
                        buildIdentity: installedBuildIdentity,
                        isDirty: isDirty,
                        files: files.map { try GitHubSourceFile(
                            path: GitHubRepositoryPath($0.path),
                            text: $0.content,
                            mode: .regular,
                        ) },
                    )
                    let initialPaths: [GitHubRepositoryPath] = if case let .screen(context) =
                        origin,
                        let path = context.source?
                        .path
                    {
                        try [GitHubRepositoryPath(path)]
                    } else { [] }
                    configuration = try PortholeGitHubConfiguration(
                        identity: identity,
                        source: source,
                        initialRepository: initialRepository,
                        initialBranch: initialBranch,
                        initialPaths: initialPaths,
                    )
                    githubConfiguration = configuration
                }
            }
            if await configuration.client.configuredClientID() == nil {
                configuration.model.requireClientIDConfiguration(using: configuration.client)
            }
            try await configuration.bind(registry: registry, scope: scope)
            guard sessionID == session,
                  origin?.scope == scope else { throw PortholeError.staleScope }
            attachGitHub(model: configuration.model)
            githubConfigurationError = nil
        } catch {
            if sessionID == session, origin?.scope == scope {
                githubConfigurationError = error.localizedDescription
            }
            throw error
        }
    }
}

/// This adapter deliberately has no publication capability. Native review owns the publication
/// entry point.
enum PortholeGitHubWorkspaceCapabilities {
    static func install(
        store: GitHubWorkspaceStore,
        client: any GitHubRepositoryReading,
        installedSource: GitHubInstalledSource,
        registry: PortholeRegistry,
        scope: PortholeScopeToken,
    ) async throws {
        try await add(
            "porthole.github.workspace",
            summary: "Read the isolated repository workspace revision, loaded files, patch, and saved review.",
            parameters: [],
            effect: .read,
            registry: registry,
            scope: scope,
        ) { _, _ in
            try await summary(store.snapshot())
        }
        try await add(
            "porthole.github.load",
            summary: "Load selected repository text at an immutable commit into the isolated workspace. Existing edits must be discarded in the native UI before replacing its base.",
            parameters: [
                text("owner"),
                text("repository"),
                text("branch"),
                .init(
                    name: "paths",
                    summary: "Repository paths to load",
                    schema: .array(.string),
                    required: true,
                ),
            ],
            effect: .isolated,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            guard case let .array(paths) = invocation.arguments["paths"],
                  paths.count <= 20
            else {
                throw PortholeError.invalidArguments("Load at most 20 text files at once.")
            }
            let selected = try paths.map { value in
                guard let path = value.stringValue
                else { throw PortholeError.invalidArguments("File paths must be strings.") }
                return try GitHubRepositoryPath(path)
            }
            let repository = try GitHubRepository(
                owner: string("owner", invocation),
                name: string("repository", invocation),
            )
            let branch = try string("branch", invocation)
            let current = try await store.loadedSnapshot()
            if case .publicationUncertain = current?
                .review { throw GitHubError.publicationReconciliationRequired }
            let base: GitHubRepositorySnapshot = if let captured = current?.workspace
                .repositoryBase,
                captured.repository == repository, captured.branch == branch
            {
                try await client.snapshot(
                    base: captured,
                    paths: selected,
                    maximumFileBytes: 1024 * 1024,
                )
            } else {
                try await client.snapshot(
                    repository: repository,
                    branch: branch,
                    paths: selected,
                    maximumFileBytes: 1024 * 1024,
                )
            }
            return try await summary(store.load(base: base, installedSource: installedSource))
        }
        try await add(
            "porthole.github.read",
            summary: "Read installed, base, or working text for a loaded repository path. Installed source is evidence and never enters the patch implicitly.",
            parameters: [text("path"), text("source")],
            effect: .read,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            let snapshot = try await store.snapshot()
            let path = try GitHubRepositoryPath(string("path", invocation))
            let file: GitHubSourceFile?
            switch try string("source", invocation) {
                case "installed": file = snapshot.workspace.installedSource.files
                .first { $0.path == path }
                case "base": file = snapshot.workspace.repositoryBase.files
                .first { $0.path == path }
                case "working": file = snapshot.workspace.file(at: path)
                default: throw PortholeError
                .invalidArguments("source must be installed, base, or working")
            }
            guard let file else { throw GitHubError.missingBaseFile }
            return .object([
                "revision": .string(snapshot.revision.uuidString),
                "path": .string(path.rawValue),
                "text": .string(file.text),
                "mode": .string(file.mode.rawValue),
            ])
        }
        try await add(
            "porthole.github.set_text",
            summary: "Edit a text file only in the isolated patch workspace. Supply the exact current revision to avoid overwriting concurrent edits. This does not publish or change the running app.",
            parameters: [text("revision"), text("path"), text("text"), text("mode")],
            effect: .isolated,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            guard let mode = try GitHubTextFileMode(rawValue: string("mode", invocation))
            else { throw PortholeError.invalidArguments("mode must be 100644 or 100755") }
            return try await summary(store.setText(
                string("text", invocation),
                at: GitHubRepositoryPath(string("path", invocation)),
                mode: mode,
                expectedRevision: revision(invocation),
            ))
        }
        try await add(
            "porthole.github.remove",
            summary: "Delete a file only from the isolated patch workspace at the exact current revision.",
            parameters: [text("revision"), text("path")],
            effect: .isolated,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            try await summary(store.remove(
                at: GitHubRepositoryPath(string("path", invocation)),
                expectedRevision: revision(invocation),
            ))
        }
        try await add(
            "porthole.github.prepare_review",
            summary: "Save an immutable patch for native review. Prefer invented regression fixtures. Declare personal evidence if the description or changed files contain captured locations, logs, records, screenshots, or personal values. Only the phone can approve personal evidence and publish.",
            parameters: [
                text("revision"),
                text("title"),
                text("body"),
                .init(
                    name: "evidence",
                    summary: "synthetic or personal; personal requires native per-proposal consent",
                    schema: .string,
                    required: true,
                ),
            ],
            effect: .isolated,
            registry: registry,
            scope: scope,
        ) { invocation, _ in
            let evidence = try GitHubReviewEvidence(rawValue: string("evidence", invocation))
            guard let evidence
            else {
                throw PortholeError.invalidArguments("Evidence must be synthetic or personal.")
            }
            let author = try await client.account()
            return try await summary(store.prepare(
                title: string("title", invocation),
                body: string("body", invocation),
                evidence: evidence,
                author: author,
                at: Date(),
                expectedRevision: revision(invocation),
            ))
        }
    }

    private static func summary(_ snapshot: GitHubWorkspaceSnapshot) throws -> PortholeValue {
        let base = snapshot.workspace.repositoryBase
        var result: [String: PortholeValue] = try [
            "revision": .string(snapshot.revision.uuidString),
            "repository": .string("\(base.repository.owner)/\(base.repository.name)"),
            "branch": .string(base.branch),
            "commit": .string(base.commit.rawValue),
            "installedBuild": .string(snapshot.workspace.installedSource.buildIdentity),
            "installedSourceIsDirty": .bool(snapshot.workspace.installedSource.isDirty),
            "loadedPaths": .array(base.files.map { .string($0.path.rawValue) }),
            "diff": .string(GitHubPatchReview.unifiedDiff(for: snapshot.workspace.patch)),
        ]
        switch snapshot.review {
            case .unreviewed: result["review"] = .string("unreviewed")
            case let .prepared(proposal), let .publicationUncertain(proposal), let .published(
            proposal,
            _,
        ):
                result["review"] = try .object([
                    "proposalID": .string(proposal.proposalID.uuidString),
                    "title": .string(proposal.title),
                    "body": .string(proposal.body),
                    "evidence": .string(proposal.evidence.rawValue),
                    "fingerprint": .string(proposal.fingerprint),
                ])
        }
        if case .publicationUncertain = snapshot.review {
            result["publicationRequiresReconciliation"] = .bool(true)
        }
        return .object(result)
    }

    private static func text(_ name: String) -> PortholeParameter {
        .init(
            name: name,
            summary: name,
            schema: .string,
            required: true,
        )
    }

    private static func string(_ name: String, _ invocation: PortholeInvocation) throws -> String {
        guard let value = invocation.arguments[name]?.stringValue
        else { throw PortholeError.invalidArguments("Missing \(name)") }
        return value
    }

    private static func revision(_ invocation: PortholeInvocation) throws -> UUID {
        guard let revision = try UUID(uuidString: string("revision", invocation))
        else { throw PortholeError.invalidArguments("revision must be a UUID") }
        return revision
    }

    private static func add(
        _ name: String,
        summary: String,
        parameters: [PortholeParameter],
        effect: PortholeEffect,
        registry: PortholeRegistry,
        scope: PortholeScopeToken,
        handler: @escaping PortholeRegistry.Handler,
    ) async throws {
        try await registry.register(
            .init(
                id: .init(rawValue: name),
                module: .init(rawValue: "PortholeGitHub"),
                name: name,
                summary: summary,
                parameters: parameters,
                result: .any,
                effect: effect,
                source: nil,
                ownership: .adapter,
                availability: .callable,
            ),
            in: scope,
            handler: handler,
        )
    }
}
