import Foundation

public enum RepositoryRevision: String, Codable, Sendable {
    case base
    case head
}

public enum AnalysisToolName: String, Codable, Sendable {
    case listPaths = "list_paths"
    case readFile = "read_file"
    case searchPaths = "search_paths"
}

public struct AnalysisToolCall: Hashable, Codable, Sendable {
    public let name: AnalysisToolName
    public let revision: RepositoryRevision
    public let path: String?
    public let query: String?
    public let prefix: String?
    public let limit: Int?

    public init(
        name: AnalysisToolName,
        revision: RepositoryRevision,
        path: String?,
        query: String?,
        prefix: String?,
        limit: Int?,
    ) {
        self.name = name
        self.revision = revision
        self.path = path
        self.query = query
        self.prefix = prefix
        self.limit = limit
    }
}

public struct AnalysisToolOutput: Hashable, Codable, Sendable {
    public let revision: RepositoryRevision
    public let path: String?
    public let paths: [String]
    public let text: String?
    public let treeIsComplete: Bool

    public init(
        revision: RepositoryRevision,
        path: String?,
        paths: [String],
        text: String?,
        treeIsComplete: Bool,
    ) {
        self.revision = revision
        self.path = path
        self.paths = paths
        self.text = text
        self.treeIsComplete = treeIsComplete
    }
}

public struct AnalysisToolMetrics: Hashable, Sendable {
    public let toolCalls: Int
    public let filesRetrieved: Int
    public let bytesRetrieved: Int

    public init(toolCalls: Int, filesRetrieved: Int, bytesRetrieved: Int) {
        self.toolCalls = toolCalls
        self.filesRetrieved = filesRetrieved
        self.bytesRetrieved = bytesRetrieved
    }
}

/// One shared budget spans every chunk and turn in an explicit analysis run.
public actor AnalysisRunBudgetController {
    private let limits: AnalysisBudget
    private var providerCalls = 0
    private var turns = 0
    private var toolCalls = 0
    private var filesRetrieved = 0
    private var bytesRetrieved = 0

    public init(limits: AnalysisBudget) {
        self.limits = limits
    }

    public func claimProviderCall() throws {
        guard providerCalls < limits.maximumProviderCalls else {
            throw AIAnalysisError.providerCallLimitReached
        }
        providerCalls += 1
    }

    public func claimToolTurn() throws {
        guard turns < limits.maximumTurns else {
            throw AIAnalysisError.turnLimitReached
        }
        turns += 1
    }

    public func recordToolOutput(byteCount: Int, retrievedFile: Bool) throws {
        guard byteCount >= 0,
              bytesRetrieved + byteCount <= limits.extraContextBytes
        else {
            throw AIAnalysisError.contextBudgetExceeded
        }
        toolCalls += 1
        bytesRetrieved += byteCount
        if retrievedFile { filesRetrieved += 1 }
    }

    public func providerCallCount() -> Int {
        providerCalls
    }

    public func toolMetrics() -> AnalysisToolMetrics {
        AnalysisToolMetrics(
            toolCalls: toolCalls,
            filesRetrieved: filesRetrieved,
            bytesRetrieved: bytesRetrieved,
        )
    }
}

/// Executes the only repository operations a provider may request. Every read
/// is pinned to the PR's exact base or head tree, and submodule entries are not
/// represented by `RepositoryTree`.
public actor AnalysisRepositoryTools {
    public static let maximumFileBytes = 256 * 1024

    private let github: any GitHubReading
    private let repository: RepositoryID
    private let baseOID: GitObjectID
    private let headOID: GitObjectID
    private let budget: AnalysisRunBudgetController
    private var trees: [RepositoryRevision: RepositoryTree] = [:]

    public init(
        github: any GitHubReading,
        repository: RepositoryID,
        baseOID: GitObjectID,
        headOID: GitObjectID,
        budget: AnalysisRunBudgetController,
    ) {
        self.github = github
        self.repository = repository
        self.baseOID = baseOID
        self.headOID = headOID
        self.budget = budget
    }

    public func execute(_ call: AnalysisToolCall) async throws -> AnalysisToolOutput {
        let output: AnalysisToolOutput
        let retrievedFile: Bool
        switch call.name {
            case .listPaths:
                let tree = try await tree(for: call.revision)
                let prefix = try normalizedOptionalPath(call.prefix)
                let limit = try validatedLimit(call.limit)
                let values = tree.entries.lazy
                    .filter { $0.kind == .blob }
                    .map(\.path)
                    .filter { path in prefix.map { path.hasPrefix($0) } ?? true }
                    .prefix(limit)
                output = AnalysisToolOutput(
                    revision: call.revision,
                    path: nil,
                    paths: Array(values),
                    text: nil,
                    treeIsComplete: tree.isComplete,
                )
                retrievedFile = false
            case .searchPaths:
                let tree = try await tree(for: call.revision)
                let query = call.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !query.isEmpty, query.count <= 200 else {
                    throw AIAnalysisError.invalidToolRequest
                }
                let limit = try validatedLimit(call.limit)
                let values = tree.entries.lazy
                    .filter { $0.kind == .blob && $0.path.contains(query) }
                    .map(\.path)
                    .prefix(limit)
                output = AnalysisToolOutput(
                    revision: call.revision,
                    path: nil,
                    paths: Array(values),
                    text: nil,
                    treeIsComplete: tree.isComplete,
                )
                retrievedFile = false
            case .readFile:
                let path = try normalizedRequiredPath(call.path)
                let tree = try await tree(for: call.revision)
                guard let entry = tree.entries.first(where: {
                    $0.kind == .blob && $0.path == path
                }) else {
                    throw AIAnalysisError.invalidToolRequest
                }
                if let byteCount = entry.byteCount,
                   byteCount > Self.maximumFileBytes
                {
                    throw AIAnalysisError.fileTooLarge
                }
                let data = try await github.blob(
                    repository: repository,
                    oid: entry.oid,
                    path: path,
                )
                guard data.count <= Self.maximumFileBytes else {
                    throw AIAnalysisError.fileTooLarge
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw AIAnalysisError.invalidToolRequest
                }
                output = AnalysisToolOutput(
                    revision: call.revision,
                    path: path,
                    paths: [],
                    text: text,
                    treeIsComplete: tree.isComplete,
                )
                retrievedFile = true
        }

        let data = try JSONEncoder.patchlightTools.encode(output)
        try await budget.recordToolOutput(
            byteCount: data.count,
            retrievedFile: retrievedFile,
        )
        return output
    }

    private func tree(for revision: RepositoryRevision) async throws -> RepositoryTree {
        if let value = trees[revision] { return value }
        let oid = revision == .base ? baseOID : headOID
        let value = try await github.tree(repository: repository, oid: oid)
        trees[revision] = value
        return value
    }

    private func normalizedRequiredPath(_ value: String?) throws -> String {
        guard let normalized = try normalizedOptionalPath(value), !normalized.isEmpty else {
            throw AIAnalysisError.invalidToolRequest
        }
        return normalized
    }

    private func normalizedOptionalPath(_ value: String?) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0"),
              !trimmed.split(separator: "/").contains("..")
        else {
            throw AIAnalysisError.invalidToolRequest
        }
        return trimmed
    }

    private func validatedLimit(_ value: Int?) throws -> Int {
        let limit = value ?? 100
        guard (1 ... 200).contains(limit) else {
            throw AIAnalysisError.invalidToolRequest
        }
        return limit
    }
}

extension JSONEncoder {
    fileprivate static var patchlightTools: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
