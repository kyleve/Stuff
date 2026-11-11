import Observation
import SwiftUI

/// Retains each scroll role's current context. Replacing a context detaches its old bindings.
@MainActor
public final class BScrollRestorationStore {
    struct Key: Hashable {
        let view: ObjectIdentifier
        let role: AnyHashable
        let content: ObjectIdentifier
    }

    private struct Record {
        let context: AnyHashable
        let entry: AnyObject
    }

    @Observable
    final class Entry<ID: Hashable & Sendable> {
        var position = ScrollPosition(idType: ID.self) {
            didSet {
                guard oldValue != position, position.isPositionedByUser else { return }
                anchor = .top
                isInitialized = true
                userRevision += 1
            }
        }

        private(set) var userRevision = 0
        var isInitialized = false
        var anchor: UnitPoint?
    }

    private var records: [Key: Record] = [:]

    public init() {}

    func entry<ID: Hashable & Sendable>(
        for key: Key,
        context: AnyHashable,
        idType _: ID.Type,
    ) -> Entry<ID> {
        if let record = records[key], record.context == context,
           let entry = record.entry as? Entry<ID>
        {
            return entry
        }
        let entry = Entry<ID>()
        records[key] = Record(context: context, entry: entry)
        return entry
    }
}

extension EnvironmentValues {
    @Entry var bScrollRestorationStore: BScrollRestorationStore?
}
