import Foundation
import PortholeCore

/// Owns debugger references. Eviction removes metadata and retained copies, never application
/// state.
struct PortholeObjectStore {
    struct Entry {
        enum Lifetime {
            case retained(PortholeObjectRetention)
            case child(parent: PortholeObjectReference, key: PortholeObjectChildKey)
        }

        let reference: PortholeObjectReference
        let value: any Sendable
        let lifetime: Lifetime
    }

    private let capacity: Int
    private var entries: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private var leases: [UUID: Set<UUID>] = [:]

    init(capacity: Int) {
        precondition(capacity > 0); self.capacity = capacity
    }

    func references(in scope: PortholeScopeToken) -> [PortholeObjectReference] {
        entries.values.filter { $0.reference.scope == scope }.map(\.reference)
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    mutating func retain(
        _ value: some Sendable,
        typeName: String,
        scope: PortholeScopeToken,
        retention: PortholeObjectRetention,
        operationID: UUID?,
    ) throws -> PortholeObjectReference {
        if case let .bounded(pool, maximum) = retention {
            guard maximum > 0
            else {
                throw PortholeError.invalidArguments("Object retention count must be positive")
            }
            let members = entries.values.filter { entry in
                guard entry.reference.scope == scope,
                      case let .retained(.bounded(existing, _)) = entry.lifetime
                else { return false }
                return existing == pool
            }
            guard members.allSatisfy({ $0.lifetime.matches(retention) }) else {
                throw PortholeError
                    .invalidArguments("An object pool cannot change its retention limit")
            }
            if members.count >= maximum {
                let candidates = Set(members.map(\.reference.id))
                guard let victim = order.first(where: { candidates.contains($0) && canRemove($0) })
                else { throw PortholeError.capacityExceeded }
                remove(victim)
            }
        }
        try makeRoom(protecting: [])
        return insert(
            value,
            typeName: typeName,
            scope: scope,
            lifetime: .retained(retention),
            operationID: operationID,
        )
    }

    mutating func retainChild(
        _ value: some Sendable,
        typeName: String,
        parent: PortholeObjectReference,
        key: PortholeObjectChildKey,
        operationID: UUID?,
    ) throws -> PortholeObjectReference {
        _ = try entry(for: parent, operationID: operationID)
        if let existing = entries.values.first(where: {
            guard case let .child(owner, field) = $0.lifetime else { return false }
            return owner == parent && field == key
        }) {
            guard existing.reference.typeName == typeName
            else { throw PortholeError.wrongObjectType(typeName) }
            _ = try entry(for: existing.reference, operationID: operationID)
            return existing.reference
        }
        try makeRoom(protecting: ancestors(of: parent.id))
        return insert(
            value,
            typeName: typeName,
            scope: parent.scope,
            lifetime: .child(parent: parent, key: key),
            operationID: operationID,
        )
    }

    mutating func entry(
        for reference: PortholeObjectReference,
        operationID: UUID?,
    ) throws -> Entry {
        guard let entry = entries[reference.id],
              entry.reference == reference else { throw PortholeError.unknownObject }
        let family = ancestors(of: reference.id)
        touch(family)
        if let operationID { leases[operationID, default: []].formUnion(family) }
        return entry
    }

    mutating func lease(_ references: [PortholeObjectReference], operationID: UUID) throws {
        do {
            for reference in references {
                _ = try entry(for: reference, operationID: operationID)
            }
        } catch { leases[operationID] = nil; throw error }
    }

    mutating func finish(operationID: UUID) {
        leases[operationID] = nil
    }

    mutating func release(_ reference: PortholeObjectReference) throws {
        guard entries[reference.id]?.reference == reference
        else { throw PortholeError.unknownObject }
        guard canRemove(reference.id) else { throw PortholeError.operationInProgress }
        remove(reference.id)
    }

    mutating func invalidate(_ scope: PortholeScopeToken) {
        for reference in references(in: scope) {
            remove(reference.id)
        }
    }

    private mutating func makeRoom(protecting: Set<UUID>) throws {
        guard entries.count >= capacity else { return }
        guard let victim = order.first(where: { candidate in
            guard !protecting.contains(candidate),
                  let entry = entries[candidate] else { return false }
            if case .retained(.scope) = entry.lifetime { return false }
            return canRemove(candidate) && descendants(of: candidate).isDisjoint(with: protecting)
        }) else { throw PortholeError.capacityExceeded }
        remove(victim)
    }

    private mutating func insert(
        _ value: some Sendable,
        typeName: String,
        scope: PortholeScopeToken,
        lifetime: Entry.Lifetime,
        operationID: UUID?,
    ) -> PortholeObjectReference {
        let reference = PortholeObjectReference(id: UUID(), scope: scope, typeName: typeName)
        entries[reference.id] = Entry(reference: reference, value: value, lifetime: lifetime)
        order.append(reference.id)
        if let operationID {
            leases[operationID, default: []].formUnion(ancestors(of: reference.id))
        }
        return reference
    }

    private func canRemove(_ objectID: UUID) -> Bool {
        let family = descendants(of: objectID)
        return leases.values.allSatisfy { $0.isDisjoint(with: family) }
    }

    private func ancestors(of objectID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [objectID]
        var current = objectID
        while let entry = entries[current], case let .child(parent, _) = entry.lifetime {
            result.insert(parent.id); current = parent.id
        }
        return result
    }

    private func descendants(of objectID: UUID) -> Set<UUID> {
        var result: Set<UUID> = [objectID]
        var changed = true
        while changed {
            changed = false
            for entry in entries.values {
                if case let .child(parent, _) = entry.lifetime, result.contains(parent.id),
                   result.insert(entry.reference.id).inserted { changed = true }
            }
        }
        return result
    }

    private mutating func touch(_ objectIDs: Set<UUID>) {
        let touched = order.filter { objectIDs.contains($0) }
        order.removeAll { objectIDs.contains($0) }; order.append(contentsOf: touched)
    }

    private mutating func remove(_ objectID: UUID) {
        let removed = descendants(of: objectID)
        for objectID in removed {
            entries[objectID] = nil
        }
        order.removeAll { removed.contains($0) }
    }
}

extension PortholeObjectStore.Entry.Lifetime {
    fileprivate func matches(_ retention: PortholeObjectRetention) -> Bool {
        guard case let .retained(existing) = self else { return false }
        return existing == retention
    }
}
