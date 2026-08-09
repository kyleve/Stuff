import Foundation

public enum DiffSide: String, Codable, Sendable {
    case base = "B"
    case head = "H"
}

public enum DiffLineKind: String, Codable, Sendable {
    case context = "C"
    case addition = "A"
    case deletion = "D"
    case metadata = "M"
}

/// A stable comment anchor independent of rendered row indices.
public struct DiffAnchor: Hashable, Codable, Sendable {
    public let path: String
    public let side: DiffSide
    public let commitOID: GitObjectID
    public let blobOID: GitObjectID?
    public let line: Int?
    public let startLine: Int?
    public let contextFingerprint: String

    public init(
        path: String,
        side: DiffSide,
        commitOID: GitObjectID,
        blobOID: GitObjectID?,
        line: Int?,
        startLine: Int?,
        contextFingerprint: String,
    ) {
        self.path = path
        self.side = side
        self.commitOID = commitOID
        self.blobOID = blobOID
        self.line = line
        self.startLine = startLine
        self.contextFingerprint = contextFingerprint
    }
}

public struct DiffLine: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let kind: DiffLineKind
    public let oldLine: Int?
    public let newLine: Int?
    public let text: String

    public init(
        id: ID,
        kind: DiffLineKind,
        oldLine: Int?,
        newLine: Int?,
        text: String,
    ) {
        self.id = id
        self.kind = kind
        self.oldLine = oldLine
        self.newLine = newLine
        self.text = text
    }
}

public struct DiffHunk: Identifiable, Hashable, Codable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]

    public init(
        id: ID,
        header: String,
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        lines: [DiffLine],
    ) {
        self.id = id
        self.header = header
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.lines = lines
    }
}

public enum DiffFileStatus: String, Codable, Sendable {
    case added = "A"
    case modified = "M"
    case removed = "D"
    case renamed = "R"
    case copied = "C"
    case changed = "T"
}

public enum DiffContentAvailability: Hashable, Codable, Sendable {
    case complete
    case binary
    case tooLarge(baseBytes: Int?, headBytes: Int?)
    case undecodable
    case unavailable(reason: String)
}

public struct DiffFile: Identifiable, Hashable, Codable, Sendable {
    public var id: String {
        path
    }

    public let path: String
    public let previousPath: String?
    public let status: DiffFileStatus
    public let additions: Int
    public let deletions: Int
    public let baseBlobOID: GitObjectID?
    public let headBlobOID: GitObjectID?
    public let availability: DiffContentAvailability
    public let hunks: [DiffHunk]

    public init(
        path: String,
        previousPath: String?,
        status: DiffFileStatus,
        additions: Int,
        deletions: Int,
        baseBlobOID: GitObjectID?,
        headBlobOID: GitObjectID?,
        availability: DiffContentAvailability,
        hunks: [DiffHunk],
    ) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.baseBlobOID = baseBlobOID
        self.headBlobOID = headBlobOID
        self.availability = availability
        self.hunks = hunks
    }
}

/// The five monotonic visibility thresholds exposed by Patchlight's slider.
public enum ReviewDepth: Int, CaseIterable, Codable, Comparable, Sendable {
    case critical = 0
    case focused = 1
    case balanced = 2
    case thorough = 3
    case everything = 4

    public static func < (lhs: ReviewDepth, rhs: ReviewDepth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ReviewCategory: String, Codable, Sendable {
    case risk = "R"
    case behavior = "B"
    case tests = "T"
    case documentation = "D"
    case generated = "G"
    case mechanical = "M"
    case unknown = "U"
}

/// One deterministic or AI-assisted hunk classification.
public struct ReviewAssessment: Hashable, Codable, Sendable {
    public let hunkID: DiffHunk.ID
    public let category: ReviewCategory
    public let minimumDepth: ReviewDepth
    public let confidence: Double
    public let evidence: [String]
    public let isPartial: Bool

    public init(
        hunkID: DiffHunk.ID,
        category: ReviewCategory,
        minimumDepth: ReviewDepth,
        confidence: Double,
        evidence: [String],
        isPartial: Bool,
    ) {
        self.hunkID = hunkID
        self.category = category
        self.minimumDepth = minimumDepth
        self.confidence = min(max(confidence, 0), 1)
        self.evidence = evidence
        self.isPartial = isPartial
    }
}
