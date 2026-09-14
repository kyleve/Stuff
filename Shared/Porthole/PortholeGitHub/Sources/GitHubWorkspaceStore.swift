import Foundation

/// Only this surface is supplied to diagnostic capabilities. Publication requires the native store
/// interface.
public protocol GitHubWorkspaceEditing: Sendable {
    func snapshot() async throws -> GitHubWorkspaceSnapshot
    func setText(
        _ text: String,
        at path: GitHubRepositoryPath,
        mode: GitHubTextFileMode,
        expectedRevision: UUID,
    ) async throws -> GitHubWorkspaceSnapshot
    func remove(at path: GitHubRepositoryPath, expectedRevision: UUID) async throws
        -> GitHubWorkspaceSnapshot
}

public struct GitHubWorkspaceSnapshot: Sendable {
    public let revision: UUID
    public let workspace: GitHubSourceWorkspace
    public let review: GitHubWorkspaceReview
    public let isPublishing: Bool
}

/// These case names are version-one persistence codes. Preserve them when Swift names change.
public enum GitHubWorkspaceReview: Codable, Sendable {
    case unreviewed
    case prepared(GitHubPullRequestProposal)
    case publicationUncertain(GitHubPullRequestProposal)
    case published(GitHubPullRequestProposal, GitHubPublishedPullRequest)
}

/// Persists one isolated patch workspace and its exact reviewed proposal before any GitHub
/// publication.
public actor GitHubWorkspaceStore: GitHubWorkspaceEditing {
    private struct Document: Codable {
        let version: Int
        let revision: UUID
        let installedSource: GitHubInstalledSource
        let base: GitHubRepositorySnapshot
        let changes: [GitHubFileChange]
        let review: GitHubWorkspaceReview

        func workspace() throws -> GitHubSourceWorkspace {
            guard version == 1 else { throw GitHubError.invalidResponse }
            try base.validate()
            var workspace = GitHubSourceWorkspace(
                installedSource: installedSource,
                repositoryBase: base,
            )
            guard Set(changes.map(\.path)).count == changes.count
            else { throw GitHubError.invalidResponse }
            for change in changes {
                try change.validate()
                guard change.before == base.files.first(where: { $0.path == change.path })
                else { throw GitHubError.missingBaseFile }
                if let after = change.after { try workspace.setText(
                    after.text,
                    at: change.path,
                    mode: after.mode,
                ) } else { try workspace.remove(at: change.path) }
            }
            switch review {
                case .unreviewed: break
                case let .prepared(proposal), let .publicationUncertain(proposal),
                     let .published(proposal, _):
                    try proposal.validate()
                    guard proposal.base.commit == base.commit, proposal.base.tree == base.tree,
                          proposal.base.branch == base.branch,
                          proposal.base.repository == base.repository,
                          proposal.changes == workspace.patch
                    else { throw GitHubError.branchConflict }
            }
            return workspace
        }
    }

    private enum State {
        case empty
        case ready(Document)
        case publishing(Document, GitHubPullRequestProposal)
    }

    private let storageURL: URL?
    private var state: State

    public init(storageURL: URL?) throws {
        self.storageURL = storageURL
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            let document = try JSONDecoder().decode(
                Document.self,
                from: Data(contentsOf: storageURL),
            )
            _ = try document.workspace()
            state = .ready(document)
        } else { state = .empty }
    }

    #if DEBUG
        /// Seeds an isolated preview through the same document validation used after relaunch.
        @_spi(Testing)
        public init(workspace: GitHubSourceWorkspace, review: GitHubWorkspaceReview) throws {
            storageURL = nil
            let document = Document(
                version: 1,
                revision: UUID(),
                installedSource: workspace.installedSource,
                base: workspace.repositoryBase,
                changes: workspace.patch,
                review: review,
            )
            _ = try document.workspace()
            state = .ready(document)
        }
    #endif

    public func load(
        base: GitHubRepositorySnapshot,
        installedSource: GitHubInstalledSource,
    ) throws -> GitHubWorkspaceSnapshot {
        try base.validate()
        switch state {
            case .empty: break
            case .publishing: throw GitHubError.busy
            case let .ready(document):
                try requireReconciled(document)
                if document.base.repository == base.repository, document.base.branch == base.branch,
                   document.base.commit == base.commit, document.base.tree == base.tree
                {
                    return try mergeLoadedFiles(
                        base: base,
                        installedSource: installedSource,
                        document: document,
                    )
                }
                guard document.changes.isEmpty else { throw GitHubError.branchConflict }
        }
        let paths = Set(base.files.map(\.path))
        let selectedSource = GitHubInstalledSource(
            buildIdentity: installedSource.buildIdentity,
            isDirty: installedSource.isDirty,
            files: installedSource.files.filter { paths.contains($0.path) },
        )
        let workspace = GitHubSourceWorkspace(installedSource: selectedSource, repositoryBase: base)
        return try save(workspace: workspace, review: .unreviewed)
    }

    public func snapshot() throws -> GitHubWorkspaceSnapshot {
        let document: Document
        let publishing: Bool
        switch state {
            case .empty: throw GitHubError.missingBaseFile
            case let .ready(value): document = value; publishing = false
            case let .publishing(value, _): document = value; publishing = true
        }
        return try GitHubWorkspaceSnapshot(
            revision: document.revision,
            workspace: document.workspace(),
            review: document.review,
            isPublishing: publishing,
        )
    }

    public func loadedSnapshot() throws -> GitHubWorkspaceSnapshot? {
        if case .empty = state { return nil }
        return try snapshot()
    }

    public func setText(
        _ text: String,
        at path: GitHubRepositoryPath,
        mode: GitHubTextFileMode,
        expectedRevision: UUID,
    ) throws -> GitHubWorkspaceSnapshot {
        var workspace = try editable(revision: expectedRevision).workspace()
        let previousPatch = workspace.patch
        try workspace.setText(text, at: path, mode: mode)
        guard workspace.patch != previousPatch else { return try snapshot() }
        return try save(workspace: workspace, review: .unreviewed)
    }

    public func remove(
        at path: GitHubRepositoryPath,
        expectedRevision: UUID,
    ) throws -> GitHubWorkspaceSnapshot {
        var workspace = try editable(revision: expectedRevision).workspace()
        let previousPatch = workspace.patch
        try workspace.remove(at: path)
        guard workspace.patch != previousPatch else { return try snapshot() }
        return try save(workspace: workspace, review: .unreviewed)
    }

    public func discardChanges(expectedRevision: UUID) throws -> GitHubWorkspaceSnapshot {
        var workspace = try editable(revision: expectedRevision).workspace()
        let previousPatch = workspace.patch
        workspace.discardChanges()
        guard workspace.patch != previousPatch else { return try snapshot() }
        return try save(workspace: workspace, review: .unreviewed)
    }

    public func prepare(
        title: String,
        body: String,
        evidence: GitHubReviewEvidence,
        author: GitHubAccount,
        at now: Date,
        expectedRevision: UUID,
    ) throws -> GitHubWorkspaceSnapshot {
        let workspace = try editable(revision: expectedRevision).workspace()
        let proposal = try GitHubPullRequestProposal(
            proposalID: UUID(),
            workspace: workspace,
            title: title,
            body: body,
            evidence: evidence,
            author: author,
            createdAt: now,
        )
        return try save(workspace: workspace, review: .prepared(proposal))
    }

    /// A trusted UI calls this after showing the complete saved proposal. Scripts never receive
    /// this method.
    public func beginPublication(
        proposalID: UUID,
        fingerprint: String,
    ) throws -> GitHubPullRequestProposal {
        guard case let .ready(document) = state else { throw GitHubError.busy }
        let proposal: GitHubPullRequestProposal
        switch document.review {
            case .unreviewed: throw GitHubError.emptyPatch
            case let .prepared(value), let .publicationUncertain(value),
                 let .published(value, _): proposal = value
        }
        guard proposal.proposalID == proposalID,
              try proposal.fingerprint == fingerprint else { throw GitHubError.branchConflict }
        // The remote may commit a write after cancellation or a lost reply. Persist the
        // proposal lock before handing it to the publisher, including on the first attempt.
        let uncertain = Document(
            version: document.version,
            revision: UUID(),
            installedSource: document.installedSource,
            base: document.base,
            changes: document.changes,
            review: .publicationUncertain(proposal),
        )
        try persist(uncertain)
        state = .publishing(uncertain, proposal)
        return proposal
    }

    public func finishPublication(
        _ result: GitHubPublishedPullRequest,
        proposalID: UUID,
        fingerprint: String,
    ) throws
        -> GitHubWorkspaceSnapshot
    {
        guard case let .publishing(document, proposal) = state else { throw GitHubError.busy }
        guard proposal.proposalID == proposalID,
              try proposal.fingerprint == fingerprint else { throw GitHubError.branchConflict }
        return try save(workspace: document.workspace(), review: .published(proposal, result))
    }

    public func publicationFailed(proposalID: UUID, fingerprint: String) throws {
        guard case let .publishing(document, proposal) = state else { throw GitHubError.busy }
        guard proposal.proposalID == proposalID,
              try proposal.fingerprint == fingerprint else { throw GitHubError.branchConflict }
        state = .ready(document)
    }

    private func editable(revision: UUID) throws -> Document {
        guard case let .ready(document) = state else { throw GitHubError.busy }
        try requireReconciled(document)
        guard document.revision == revision else { throw GitHubError.branchConflict }
        return document
    }

    private func requireReconciled(_ document: Document) throws {
        if case .publicationUncertain = document.review {
            throw GitHubError.publicationReconciliationRequired
        }
    }

    private func mergeLoadedFiles(
        base: GitHubRepositorySnapshot,
        installedSource: GitHubInstalledSource,
        document: Document,
    ) throws -> GitHubWorkspaceSnapshot {
        guard base.knownPaths == document.base.knownPaths else { throw GitHubError.branchConflict }
        var files = Dictionary(uniqueKeysWithValues: document.base.files.map { ($0.path, $0) })
        for file in base.files {
            guard files[file.path] == nil || files[file.path] == file
            else { throw GitHubError.branchConflict }
            files[file.path] = file
        }
        let expanded = try GitHubRepositorySnapshot(
            repository: base.repository,
            branch: base.branch,
            commit: base.commit,
            tree: base.tree,
            knownPaths: base.knownPaths,
            files: files.values.sorted { $0.path < $1.path },
        )
        var evidence = Dictionary(uniqueKeysWithValues: document.installedSource.files.map { (
            $0.path,
            $0,
        ) })
        if installedSource.buildIdentity == document.installedSource.buildIdentity {
            for file in installedSource.files
                where files[file.path] != nil
            {
                evidence[file.path] = file
            }
        }
        let source = GitHubInstalledSource(
            buildIdentity: document.installedSource.buildIdentity,
            isDirty: document.installedSource.isDirty,
            files: evidence.values.sorted { $0.path < $1.path },
        )
        var workspace = GitHubSourceWorkspace(installedSource: source, repositoryBase: expanded)
        for change in document.changes {
            if let after = change.after { try workspace.setText(
                after.text,
                at: change.path,
                mode: after.mode,
            ) } else { try workspace.remove(at: change.path) }
        }
        return try save(workspace: workspace, review: document.review)
    }

    private func save(
        workspace: GitHubSourceWorkspace,
        review: GitHubWorkspaceReview,
    ) throws -> GitHubWorkspaceSnapshot {
        let document = Document(
            version: 1,
            revision: UUID(),
            installedSource: workspace.installedSource,
            base: workspace.repositoryBase,
            changes: workspace.patch,
            review: review,
        )
        try persist(document)
        state = .ready(document)
        return try snapshot()
    }

    private func persist(_ document: Document) throws {
        if let storageURL {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try JSONEncoder().encode(document).write(to: storageURL, options: .atomic)
        }
    }
}
