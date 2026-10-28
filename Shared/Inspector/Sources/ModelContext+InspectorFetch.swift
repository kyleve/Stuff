import Foundation
import SwiftData

extension ModelContext {
    /// The number of persisted rows of `type`, opening the existential metatype
    /// so the generic `fetchCount` can infer its `PersistentModel`.
    func inspectorCount(of type: any PersistentModel.Type) -> Int {
        func open<T: PersistentModel>(_: T.Type) -> Int {
            (try? fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return open(type)
    }

    /// The persisted row of `type` with `id`, or `nil` if it is no longer in the
    /// store. Uses a `persistentModelID` predicate (not `model(for:)`, which
    /// traps on a missing id) so a row deleted between loading the table and
    /// drilling into it degrades gracefully. Fetch failures still throw so a
    /// destructive caller cannot confuse an unavailable row with an unavailable
    /// store. Opens the existential so the generic `fetch` can infer its
    /// `PersistentModel`.
    func inspectorModel(
        _ type: any PersistentModel.Type,
        id: PersistentIdentifier,
    ) throws -> (any PersistentModel)? {
        func open<T: PersistentModel>(_: T.Type) throws -> (any PersistentModel)? {
            var descriptor =
                FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
            descriptor.fetchLimit = 1
            return try fetch(descriptor).first
        }
        return try open(type)
    }

    /// The first `limit` persisted rows of `type` (a `nil` limit fetches every
    /// row), as type-erased models, opening the existential metatype so the
    /// generic `fetch` can infer its `PersistentModel`.
    ///
    /// The inspector pages by *growing this prefix* rather than by `fetchOffset`:
    /// "load more" re-fetches a longer prefix in one query and replaces the
    /// view's rows. A single fetch is internally consistent, so pages can't
    /// overlap or skip even though `FetchDescriptor` has no sort to make an
    /// offset's boundary stable.
    func inspectorFetch(
        _ type: any PersistentModel.Type,
        limit: Int?,
    ) -> [any PersistentModel] {
        func open<T: PersistentModel>(_: T.Type) -> [any PersistentModel] {
            var descriptor = FetchDescriptor<T>()
            if let limit {
                descriptor.fetchLimit = limit
            }
            return (try? fetch(descriptor)) ?? []
        }
        return open(type)
    }

    /// The persisted rows of `type` whose ids are in `ids`, fetched in a single
    /// query and returned keyed by id, opening the existential so the generic
    /// `fetch` can infer its `PersistentModel`.
    ///
    /// Used to materialize a relationship's related rows in one round-trip rather
    /// than one `inspectorModel(_:id:)` per id. The fetch returns the rows fully
    /// realized (attributes loaded), unlike `model(for:)`, which yields a fault.
    /// Returns only the ids that still resolve, so a related row deleted out from
    /// under the relationship is simply dropped.
    func inspectorModels(
        _ type: any PersistentModel.Type,
        ids: [PersistentIdentifier],
    ) -> [PersistentIdentifier: any PersistentModel] {
        guard !ids.isEmpty else { return [:] }
        func open<T: PersistentModel>(_: T.Type) -> [PersistentIdentifier: any PersistentModel] {
            let wanted = Set(ids)
            var descriptor =
                FetchDescriptor<T>(predicate: #Predicate { wanted.contains($0.persistentModelID) })
            descriptor.fetchLimit = wanted.count
            let fetched = (try? fetch(descriptor)) ?? []
            return Dictionary(
                fetched.map { ($0.persistentModelID, $0 as any PersistentModel) },
                uniquingKeysWith: { first, _ in first },
            )
        }
        return open(type)
    }

    /// Delete one persisted row without letting its non-Sendable model instance
    /// escape this context.
    func inspectorDelete(
        _ type: any PersistentModel.Type,
        id: PersistentIdentifier,
    ) throws {
        guard let model = try inspectorModel(type, id: id) else { return }
        delete(model)
        try save()
    }

    /// Delete every persisted row of `type`, opening the existential metatype so
    /// SwiftData's generic batch-delete API can infer the model.
    func inspectorDeleteAll(_ type: any PersistentModel.Type) throws {
        func open<T: PersistentModel>(_: T.Type) throws {
            try delete(model: T.self)
            try save()
        }
        try open(type)
    }
}
