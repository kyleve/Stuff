import Foundation

/// One entry in the crash-durability journal: the log-layer envelope that
/// PeriscopeCore writes through JournalKit's payload-agnostic `Journal`.
///
/// Entries encode as versioned JSON (`{"v":1,"kind":"record","payload":…}`)
/// so a future build can evolve the shape; decoding an unknown kind yields
/// `nil` rather than an error, and ingest skips it.
@_spi(Testing) public enum LogJournalEntry: Sendable, Equatable {
    /// The session the journal's records belong to — written first, so a
    /// recovered journal is attributable on its own.
    case session(LogSession)
    /// A scope definition; without these a recovered record has IDs but no
    /// hierarchy.
    case scope(LogScope)
    /// One emitted record.
    case record(LogJournalRecord)

    private static let version = 1

    /// One encoding pass: the payload nests as a JSON *object*, not
    /// re-encoded bytes — base64-wrapping the payload would inflate every
    /// entry ~33% and pay an extra encode on the emit path.
    @_spi(Testing) public func encoded() throws -> Data {
        switch self {
            case let .session(session):
                try JSONEncoder().encode(
                    Envelope(version: Self.version, kind: "session", payload: session),
                )
            case let .scope(scope):
                try JSONEncoder().encode(
                    Envelope(version: Self.version, kind: "scope", payload: scope),
                )
            case let .record(record):
                try JSONEncoder().encode(
                    Envelope(version: Self.version, kind: "record", payload: record),
                )
        }
    }

    /// Decode one journal payload. Returns `nil` for a kind this build
    /// doesn't know (a newer build wrote it — skip, don't fail); throws
    /// for malformed data. Two passes — a cheap kind peek, then the typed
    /// decode — which only ingest pays, once per launch.
    @_spi(Testing) public static func decoded(from data: Data) throws -> LogJournalEntry? {
        switch try JSONDecoder().decode(EnvelopeHeader.self, from: data).kind {
            case "session":
                try .session(JSONDecoder().decode(Envelope<LogSession>.self, from: data).payload)
            case "scope":
                try .scope(JSONDecoder().decode(Envelope<LogScope>.self, from: data).payload)
            case "record":
                try .record(JSONDecoder().decode(Envelope<LogJournalRecord>.self, from: data)
                    .payload)
            default:
                nil
        }
    }

    /// The wire shape: version + kind discriminator + the payload as a
    /// nested JSON object.
    private struct Envelope<Payload: Codable>: Codable {
        var version: Int
        var kind: String
        var payload: Payload

        private enum CodingKeys: String, CodingKey {
            case version = "v"
            case kind
            case payload
        }
    }

    /// The discriminator alone — decoded first to pick the typed decode.
    private struct EnvelopeHeader: Codable {
        var kind: String
    }
}

/// A `LogRecord` as journaled: the same durable mirror the store persists
/// (versioned payload JSON, columns, tags, call site), plus the journal
/// sequence that orders replay.
@_spi(Testing) public struct LogJournalRecord: Codable, Sendable, Equatable {
    @_spi(Testing) public var id: UUID
    @_spi(Testing) public var sequence: Int
    @_spi(Testing) public var date: Date
    @_spi(Testing) public var levelName: String
    @_spi(Testing) public var severity: Int
    @_spi(Testing) public var eventName: String
    @_spi(Testing) public var eventVersion: Int
    @_spi(Testing) public var message: String
    @_spi(Testing) public var payload: Data
    @_spi(Testing) public var scopes: [UUID]
    @_spi(Testing) public var tags: [LogTag]
    @_spi(Testing) public var spanID: UUID?
    @_spi(Testing) public var spanExitMode: String?
    @_spi(Testing) public var callFunction: String?
    @_spi(Testing) public var callFileID: String?
    @_spi(Testing) public var externalID: String?
    @_spi(Testing) public var attachments: [LogJournalAttachment]

    /// Attachment blobs above this size are omitted from the journal (the
    /// async path still delivers them when the process survives) — inlining
    /// screenshots would blow the emit-latency budget.
    @_spi(Testing) public static let maximumInlineAttachmentBytes = 64 * 1024

    @_spi(Testing) public init(record: LogRecord, sequence: Int) throws {
        id = record.id
        self.sequence = sequence
        date = record.date
        levelName = record.level.name
        severity = record.level.severity
        eventName = record.eventName
        eventVersion = record.eventVersion
        message = record.message
        payload = try JSONEncoder().encode(record.event)
        scopes = record.scopes.map(\.rawValue)
        tags = record.tags
        spanID = record.spanID?.rawValue
        spanExitMode = record.spanExit?.mode.rawValue
        callFunction = record.callSite?.function
        callFileID = record.callSite?.fileID
        externalID = record.externalID
        attachments = record.attachments.map { attachment in
            attachment.data.count <= Self.maximumInlineAttachmentBytes
                ? .inline(attachment)
                : .omitted(
                    name: attachment.name,
                    contentType: attachment.contentType,
                    byteCount: attachment.data.count,
                )
        }
    }
}

/// A journaled attachment: inlined when small, or a marker recording that
/// an oversized blob existed (its bytes only survive if the async path
/// delivered them before the crash).
@_spi(Testing) public enum LogJournalAttachment: Sendable, Equatable {
    case inline(LogAttachment)
    case omitted(name: String, contentType: LogAttachment.ContentType, byteCount: Int)
}

// Hand-written rather than synthesized Codable, for two load-bearing
// reasons: `LogAttachment`/`ContentType` don't conform (the content type
// persists via its MIME string, matching the store), and synthesized enum
// coding would freeze the *case names* into the wire format as nesting
// (`{"inline":{"_0":…}}`) — a rename would silently break old journals.
// The flat shape keeps the format independent of Swift-side naming.
extension LogJournalAttachment: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case mimeType
        case data
        case omittedByteCount
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case let .inline(attachment):
                try container.encode(attachment.name, forKey: .name)
                try container.encode(attachment.contentType.mimeType, forKey: .mimeType)
                try container.encode(attachment.data, forKey: .data)
            case let .omitted(name, contentType, byteCount):
                try container.encode(name, forKey: .name)
                try container.encode(contentType.mimeType, forKey: .mimeType)
                try container.encode(byteCount, forKey: .omittedByteCount)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let contentType = try LogAttachment.ContentType(
            mimeType: container.decode(String.self, forKey: .mimeType),
        )
        if let data = try container.decodeIfPresent(Data.self, forKey: .data) {
            self = .inline(LogAttachment(name: name, contentType: contentType, data: data))
        } else {
            self = try .omitted(
                name: name,
                contentType: contentType,
                byteCount: container.decode(Int.self, forKey: .omittedByteCount),
            )
        }
    }
}
