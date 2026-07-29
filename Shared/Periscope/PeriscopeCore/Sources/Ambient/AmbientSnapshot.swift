import Foundation

/// The ambient state as of one moment: the latest value of every stateful
/// ``AmbientKind`` observed so far.
///
/// Session metadata answers "which build, on which device"; a snapshot
/// answers "what was the system doing" — connectivity, thermal state, power
/// mode, lifecycle — and it is stamped onto *every* record, not just the
/// ambient events themselves. Correlating an error with the network state at
/// the time stops being a timestamp hunt.
///
/// Identity is the dedupe key. ``applying(_:)`` returns `self` whenever
/// nothing actually moved, so a run of records sharing one system state also
/// shares one ``id`` — and therefore one stored row.
public struct AmbientSnapshot: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    /// The latest value per kind. Momentary events
    /// (``AmbientEvent/Reporting/occurrence``) never appear here.
    public let values: [AmbientKind: String]

    public init(id: UUID, values: [AmbientKind: String]) {
        self.id = id
        self.values = values
    }

    public subscript(kind: AmbientKind) -> String? {
        values[kind]
    }

    /// The snapshot after `event`: `self` when the event is momentary or its
    /// value is already current, otherwise a **new identity** carrying the
    /// new value. Returning `self` unchanged is what keeps one row per
    /// distinct state rather than one per record.
    public func applying(_ event: AmbientEvent) -> AmbientSnapshot {
        guard event.reporting == .state, values[event.kind] != event.value else { return self }
        var updated = values
        updated[event.kind] = event.value
        return AmbientSnapshot(id: UUID(), values: updated)
    }

    /// The snapshot without `kind`: `self` when the kind isn't present
    /// (identity preserved, like ``applying(_:)``), `nil` when it was the
    /// only one — an empty snapshot is not a state, it's the absence of one.
    ///
    /// This is how a redaction-suppressed ambient event folds: the hook
    /// ruled the value unrecordable, so the snapshot forgets the kind
    /// rather than either leaking the suppressed value or keeping the
    /// stale previous one.
    public func removing(_ kind: AmbientKind) -> AmbientSnapshot? {
        guard values[kind] != nil else { return self }
        var remaining = values
        remaining[kind] = nil
        guard !remaining.isEmpty else { return nil }
        return AmbientSnapshot(id: UUID(), values: remaining)
    }

    /// Fold `event` into `snapshot`, where `nil` means nothing has been
    /// observed yet. A momentary event leaves `nil` alone, so an empty
    /// snapshot — a row claiming to describe a system state it knows nothing
    /// about — can't come into existence.
    public static func folding(
        _ event: AmbientEvent,
        into snapshot: AmbientSnapshot?,
    ) -> AmbientSnapshot? {
        guard let snapshot else {
            guard event.reporting == .state else { return nil }
            return AmbientSnapshot(id: UUID(), values: [event.kind: event.value])
        }
        return snapshot.applying(event)
    }
}

/// Lets ``AmbientSnapshot/values`` encode as a plain JSON object keyed by the
/// kind, instead of the flat alternating key/value array a dictionary with
/// non-string keys falls back to. Deliberately *not* `RawRepresentable`,
/// which would come with stdlib conformances that could change how a kind
/// encodes inside an `AmbientEvent` payload — invalidating stored rows.
extension AmbientKind: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        StringCodingKey(rawValue)
    }

    public init?(codingKey: some CodingKey) {
        self.init(codingKey.stringValue)
    }
}
