import CryptoKit
import Foundation

public struct PatchlightReviewRules: Hashable, Codable, Sendable {
    public let alwaysReview: [String]
    public let generated: [String]
    public let mechanical: [String]
    public let tests: [String]

    public init(
        alwaysReview: [String],
        generated: [String],
        mechanical: [String],
        tests: [String],
    ) {
        self.alwaysReview = alwaysReview
        self.generated = generated
        self.mechanical = mechanical
        self.tests = tests
    }
}

public struct PatchlightSnapshotRules: Hashable, Codable, Sendable {
    public let include: [String]
    public let exclude: [String]

    public init(include: [String], exclude: [String]) {
        self.include = include
        self.exclude = exclude
    }
}

public struct PatchlightLocalRepositoryOverrides: Hashable, Codable, Sendable {
    public let review: PatchlightReviewRules?
    public let snapshots: PatchlightSnapshotRules?
    public let manualSnapshotPaths: Set<String>

    public init(
        review: PatchlightReviewRules?,
        snapshots: PatchlightSnapshotRules?,
        manualSnapshotPaths: Set<String>,
    ) {
        self.review = review
        self.snapshots = snapshots
        self.manualSnapshotPaths = manualSnapshotPaths
    }

    public static let empty = PatchlightLocalRepositoryOverrides(
        review: nil,
        snapshots: nil,
        manualSnapshotPaths: [],
    )
}

public struct PatchlightRepositorySettings: Hashable, Codable, Sendable {
    public let repository: RepositoryID
    public let aiEnabled: Bool
    public let imageAIEnabled: Bool
    public let overrides: PatchlightLocalRepositoryOverrides

    public init(
        repository: RepositoryID,
        aiEnabled: Bool,
        imageAIEnabled: Bool,
        overrides: PatchlightLocalRepositoryOverrides,
    ) {
        self.repository = repository
        self.aiEnabled = aiEnabled
        self.imageAIEnabled = imageAIEnabled
        self.overrides = overrides
    }
}

public struct PatchlightRepositoryConfigurationV1: Hashable, Codable, Sendable {
    public let version: Int
    public let review: PatchlightReviewRules
    public let snapshots: PatchlightSnapshotRules

    public init(
        review: PatchlightReviewRules,
        snapshots: PatchlightSnapshotRules,
    ) {
        version = 1
        self.review = review
        self.snapshots = snapshots
    }

    public static func decode(_ data: Data) throws -> Self {
        let version = try JSONDecoder().decode(ConfigurationVersion.self, from: data).version
        guard version == 1 else {
            throw PatchlightConfigurationError.unsupportedVersion(version)
        }
        do {
            let configuration = try JSONDecoder().decode(Self.self, from: data)
            for pattern in configuration.review.alwaysReview +
                configuration.review.generated +
                configuration.review.mechanical +
                configuration.review.tests +
                configuration.snapshots.include +
                configuration.snapshots.exclude
            {
                _ = try PatchlightPathGlob(pattern)
            }
            return configuration
        } catch let error as PatchlightConfigurationError {
            throw error
        } catch {
            throw PatchlightConfigurationError.invalidJSON
        }
    }

    public var fingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            assertionFailure(
                "Patchlight's v1 repository configuration must remain encodable: \(error)",
            )
            data = Data("invalid-configuration".utf8)
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct ConfigurationVersion: Decodable {
        let version: Int
    }
}

public enum PatchlightConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidJSON
    case unsupportedVersion(Int)
    case invalidPattern(String)

    public var errorDescription: String? {
        switch self {
            case .invalidJSON:
                "The base revision's .patchlight.json is invalid; Patchlight is using built-in policy."
            case let .unsupportedVersion(version):
                "The base revision uses unsupported .patchlight.json version \(version); Patchlight is using built-in policy."
            case let .invalidPattern(pattern):
                "The Patchlight path pattern ‘\(pattern)’ is invalid."
        }
    }
}

public enum RepositoryConfigurationState: Hashable, Codable, Sendable {
    case absent
    case loaded(PatchlightRepositoryConfigurationV1)
    case invalid(String)

    private enum Code: String, Codable {
        case absent = "A"
        case loaded = "L"
        case invalid = "I"
    }

    private enum CodingKeys: String, CodingKey {
        case code = "c"
        case configuration = "v"
        case message = "m"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Code.self, forKey: .code) {
            case .absent: self = .absent
            case .loaded:
                self = try .loaded(container.decode(
                    PatchlightRepositoryConfigurationV1.self,
                    forKey: .configuration,
                ))
            case .invalid:
                self = try .invalid(container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .absent:
                try container.encode(Code.absent, forKey: .code)
            case let .loaded(configuration):
                try container.encode(Code.loaded, forKey: .code)
                try container.encode(configuration, forKey: .configuration)
            case let .invalid(message):
                try container.encode(Code.invalid, forKey: .code)
                try container.encode(message, forKey: .message)
        }
    }
}

/// Case-sensitive, slash-normalized glob matching for `*`, `**`, and `?`.
public struct PatchlightPathGlob: Hashable, Sendable {
    public let pattern: String
    private let tokens: [Token]

    public init(_ pattern: String) throws {
        let normalized = Self.normalize(pattern)
        guard !normalized.isEmpty, !normalized.contains("\0") else {
            throw PatchlightConfigurationError.invalidPattern(pattern)
        }
        self.pattern = normalized
        tokens = Self.tokenize(normalized)
    }

    public func matches(_ path: String) -> Bool {
        let characters = Array(Self.normalize(path))
        var memo: [Position: Bool] = [:]
        func visit(_ tokenIndex: Int, _ characterIndex: Int) -> Bool {
            let position = Position(token: tokenIndex, character: characterIndex)
            if let value = memo[position] { return value }
            let result: Bool = if tokenIndex == tokens.count {
                characterIndex == characters.count
            } else {
                switch tokens[tokenIndex] {
                    case let .literal(character):
                        characterIndex < characters.count &&
                            characters[characterIndex] == character &&
                            visit(tokenIndex + 1, characterIndex + 1)
                    case .single:
                        characterIndex < characters.count &&
                            characters[characterIndex] != "/" &&
                            visit(tokenIndex + 1, characterIndex + 1)
                    case .segmentWildcard:
                        visit(tokenIndex + 1, characterIndex) ||
                            (characterIndex < characters.count &&
                                characters[characterIndex] != "/" &&
                                visit(tokenIndex, characterIndex + 1))
                    case .recursiveWildcard:
                        visit(tokenIndex + 1, characterIndex) ||
                            (characterIndex < characters.count &&
                                visit(tokenIndex, characterIndex + 1))
                }
            }
            memo[position] = result
            return result
        }
        return visit(0, 0)
    }

    private static func normalize(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "\\", with: "/")
        while result.hasPrefix("./") {
            result.removeFirst(2)
        }
        while result.contains("//") {
            result = result.replacingOccurrences(of: "//", with: "/")
        }
        return result
    }

    private static func tokenize(_ pattern: String) -> [Token] {
        let characters = Array(pattern)
        var result: [Token] = []
        var index = 0
        while index < characters.count {
            switch characters[index] {
                case "*" where index + 1 < characters.count && characters[index + 1] == "*":
                    result.append(.recursiveWildcard)
                    index += 2
                case "*":
                    result.append(.segmentWildcard)
                    index += 1
                case "?":
                    result.append(.single)
                    index += 1
                case let character:
                    result.append(.literal(character))
                    index += 1
            }
        }
        return result
    }

    private enum Token: Hashable {
        case literal(Character)
        case single
        case segmentWildcard
        case recursiveWildcard
    }

    private struct Position: Hashable {
        let token: Int
        let character: Int
    }
}

public enum ReviewCorrectionKind: String, Codable, Sendable {
    case alwaysShow = "S"
    case mechanical = "M"
}

public struct ReviewCorrection: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let pullRequest: PullRequestID
    public let headOID: GitObjectID
    public let path: String
    public let hunkID: DiffHunk.ID?
    public let kind: ReviewCorrectionKind

    public init(
        id: UUID,
        pullRequest: PullRequestID,
        headOID: GitObjectID,
        path: String,
        hunkID: DiffHunk.ID?,
        kind: ReviewCorrectionKind,
    ) {
        self.id = id
        self.pullRequest = pullRequest
        self.headOID = headOID
        self.path = path
        self.hunkID = hunkID
        self.kind = kind
    }
}

public struct HunkReviewPlan: Identifiable, Hashable, Codable, Sendable {
    public var id: DiffHunk.ID {
        hunk.id
    }

    public let hunk: DiffHunk
    public let assessment: ReviewAssessment

    public init(hunk: DiffHunk, assessment: ReviewAssessment) {
        self.hunk = hunk
        self.assessment = assessment
    }
}

public struct FileReviewPlan: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        file.path
    }

    public let file: DiffFile
    public let minimumDepth: ReviewDepth
    public let hunks: [HunkReviewPlan]
    public let isSnapshot: Bool

    public init(
        file: DiffFile,
        minimumDepth: ReviewDepth,
        hunks: [HunkReviewPlan],
        isSnapshot: Bool,
    ) {
        self.file = file
        self.minimumDepth = minimumDepth
        self.hunks = hunks
        self.isSnapshot = isSnapshot
    }
}

public struct DeterministicReviewPlan: Hashable, Codable, Sendable {
    public let files: [FileReviewPlan]
    public let configurationWarning: String?

    public init(files: [FileReviewPlan], configurationWarning: String?) {
        self.files = files
        self.configurationWarning = configurationWarning
    }
}

public enum DeterministicReviewAnalyzer {
    public static func analyze(
        workspace: PullRequestWorkspace,
        localRules: PatchlightReviewRules?,
        localSnapshotRules: PatchlightSnapshotRules?,
        manualSnapshotPaths: Set<String>,
        threadPaths: Set<String>,
        draftPaths: Set<String>,
        corrections: [ReviewCorrection],
    ) -> DeterministicReviewPlan {
        let configuration: PatchlightRepositoryConfigurationV1?
        let warning: String?
        switch workspace.repositoryConfiguration {
            case .absent:
                configuration = nil
                warning = nil
            case let .loaded(value):
                configuration = value
                warning = nil
            case let .invalid(message):
                configuration = nil
                warning = message
        }
        let reviewRules = localRules ?? configuration?.review ?? builtInReviewRules
        let snapshotRules = localSnapshotRules ?? configuration?.snapshots ?? builtInSnapshotRules
        let alwaysReview = compile(reviewRules.alwaysReview)
        let generated = compile(reviewRules.generated)
        let mechanical = compile(reviewRules.mechanical)
        let tests = compile(reviewRules.tests)
        let snapshotInclude = compile(snapshotRules.include)
        let snapshotExclude = compile(snapshotRules.exclude)

        let plans = workspace.files.map { file in
            let hardSignal = !workspace.isFileListComplete ||
                file.path == ".patchlight.json" ||
                threadPaths.contains(file.path) ||
                draftPaths.contains(file.path) ||
                matches(file.path, patterns: alwaysReview) ||
                file.availability != .complete
            let fileCorrections = corrections.filter {
                $0.pullRequest == workspace.summary.id &&
                    $0.headOID == workspace.summary.headOID &&
                    $0.path == file.path
            }
            let hunkPlans = file.hunks.map { hunk in
                assessment(
                    file: file,
                    hunk: hunk,
                    hardSignal: hardSignal,
                    generated: matches(file.path, patterns: generated),
                    mechanical: matches(file.path, patterns: mechanical),
                    isTest: matches(file.path, patterns: tests),
                    corrections: fileCorrections,
                )
            }
            let minimumDepth = hardSignal
                ? .critical
                : hunkPlans.map(\.assessment.minimumDepth).min() ?? .balanced
            let snapshot = manualSnapshotPaths.contains(file.path) || isSnapshot(
                path: file.path,
                include: snapshotInclude,
                exclude: snapshotExclude,
            )
            return FileReviewPlan(
                file: file,
                minimumDepth: minimumDepth,
                hunks: hunkPlans,
                isSnapshot: snapshot,
            )
        }
        return DeterministicReviewPlan(files: plans, configurationWarning: warning)
    }

    private static func assessment(
        file: DiffFile,
        hunk: DiffHunk,
        hardSignal: Bool,
        generated: Bool,
        mechanical: Bool,
        isTest: Bool,
        corrections: [ReviewCorrection],
    ) -> HunkReviewPlan {
        let linesChanged = hunk.lines.count(where: { $0.kind == .addition || $0.kind == .deletion })
        let fileChanged = file.additions + file.deletions
        let alwaysShow = corrections.contains {
            $0.kind == .alwaysShow && ($0.hunkID == nil || $0.hunkID == hunk.id)
        }
        let markedMechanical = corrections.contains {
            $0.kind == .mechanical && ($0.hunkID == nil || $0.hunkID == hunk.id)
        }
        let sensitive = sensitiveSignal(file: file, hunk: hunk, isTest: isTest)
        let exactMechanical = exactMechanicalEvidence(hunk)

        var depth = ReviewDepth.balanced
        var category = ReviewCategory.unknown
        var evidence: [String] = []
        if generated || exactMechanical {
            depth = .everything
            category = generated ? .generated : .mechanical
            evidence
                .append(generated ? "Configured generated path" :
                    "Exact whitespace or move-only evidence")
        } else if mechanical || markedMechanical {
            depth = .thorough
            category = .mechanical
            evidence
                .append(mechanical ? "Configured mechanical path" :
                    "Local per-head mechanical correction")
        }
        if fileChanged >= 500 {
            depth = min(depth, .focused)
            evidence.append("File changes 500 or more lines")
        } else if fileChanged >= 200 {
            depth = min(depth, .balanced)
            evidence.append("File changes 200 or more lines")
        }
        if linesChanged >= 500 {
            depth = min(depth, .focused)
            evidence.append("Hunk changes 500 or more lines")
        }
        if sensitive {
            depth = min(depth, .focused)
            category = .risk
            evidence
                .append(
                    "Sensitive auth, persistence, migration, entitlement, dependency, CI, or test-deletion signal",
                )
        }
        if hardSignal || alwaysShow {
            depth = .critical
            category = .risk
            evidence
                .append(alwaysShow ? "Local per-head Always Show correction" : "Hard safety signal")
        }
        return HunkReviewPlan(
            hunk: hunk,
            assessment: ReviewAssessment(
                hunkID: hunk.id,
                category: category,
                minimumDepth: depth,
                confidence: 1,
                evidence: evidence,
                isPartial: false,
            ),
        )
    }

    private static func exactMechanicalEvidence(_ hunk: DiffHunk) -> Bool {
        let removed = hunk.lines.filter { $0.kind == .deletion }.map {
            $0.text.filter { !$0.isWhitespace }
        }
        let added = hunk.lines.filter { $0.kind == .addition }.map {
            $0.text.filter { !$0.isWhitespace }
        }
        guard !removed.isEmpty || !added.isEmpty else { return false }
        return removed.sorted() == added.sorted()
    }

    private static func sensitiveSignal(file: DiffFile, hunk: DiffHunk, isTest: Bool) -> Bool {
        let path = file.path.lowercased()
        let sensitivePathFragments = [
            "auth",
            "credential",
            "keychain",
            "persistence",
            "store",
            "schema",
            "migration",
            "entitlement",
            "package.swift",
            "package.resolved",
            "project.swift",
            ".github/",
            "ci/",
            "workflow",
            "privacyinfo",
            "info.plist",
        ]
        if sensitivePathFragments.contains(where: path.contains) { return true }
        if isTest, file.deletions > file.additions { return true }
        let text = hunk.lines.map(\.text).joined(separator: "\n").lowercased()
        return ["authorization", "access token", "refresh token", "encrypt", "decrypt"]
            .contains(where: text.contains)
    }

    private static func isSnapshot(
        path: String,
        include: [PatchlightPathGlob],
        exclude: [PatchlightPathGlob],
    ) -> Bool {
        guard path.lowercased().hasSuffix(".png") else { return false }
        if matches(path, patterns: exclude) { return false }
        if matches(path, patterns: include) { return true }
        let lowercased = path.lowercased()
        return lowercased.contains("/snapshots/") ||
            lowercased.contains("/__snapshots__/") ||
            lowercased.hasPrefix("snapshots/")
    }

    private static func compile(_ patterns: [String]) -> [PatchlightPathGlob] {
        patterns.compactMap { pattern in
            do {
                return try PatchlightPathGlob(pattern)
            } catch {
                assertionFailure("Review patterns must be validated before analysis: \(error)")
                return nil
            }
        }
    }

    private static func matches(_ path: String, patterns: [PatchlightPathGlob]) -> Bool {
        patterns.contains { $0.matches(path) }
    }

    private static let builtInReviewRules = PatchlightReviewRules(
        alwaysReview: [],
        generated: ["**/*.generated.swift", "**/Generated/**"],
        mechanical: [],
        tests: ["**/Tests/**", "**/*Tests.swift"],
    )

    private static let builtInSnapshotRules = PatchlightSnapshotRules(
        include: ["**/Snapshots/**/*.png", "**/__Snapshots__/**/*.png"],
        exclude: [],
    )
}
