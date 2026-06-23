import Foundation
import SwiftData

/// The small, well-contained runtime reflection the inspector needs to browse a
/// store whose `@Model` types it only knows at runtime.
///
/// SwiftData is statically typed: `FetchDescriptor`/`fetch` need a concrete
/// `PersistentModel` type, and there is no public API to read an attribute by
/// name off a `PersistentModel` instance. This file isolates the two pieces of
/// private-internal reflection that requires — the concrete metatype behind a
/// `Schema.Entity` and a model's stored values — so the rest of the module
/// stays on public API and a future SwiftData change only breaks (and degrades)
/// here, never crashes the app.
enum SwiftDataReflection {
    /// Best-effort `any PersistentModel.Type` behind a `Schema.Entity`.
    ///
    /// `Schema.Entity` carries the concrete model metatype in a private
    /// `_objectType` child with no public accessor. Returns `nil` if that shape
    /// ever changes, letting callers fall back to an explicitly supplied type
    /// list.
    static func metatype(of entity: Schema.Entity) -> (any PersistentModel.Type)? {
        Mirror(reflecting: entity).descendant("_objectType") as? any PersistentModel.Type
    }

    /// The stored attribute values of a model instance, keyed by attribute name.
    ///
    /// `@Model` rewrites declared properties into computed accessors over a
    /// private `_$backingData`, so a plain `Mirror` over the instance only shows
    /// synthesized storage. The values live in `_$backingData._storage` as a
    /// name-to-index lookup table (`lut.backing`) plus a parallel value array
    /// (`arr`). Returns an empty dictionary if the shape is not what we expect,
    /// so a row degrades to blank cells instead of trapping.
    static func storedValues(of model: any PersistentModel) -> [String: Any] {
        let mirror = Mirror(reflecting: model)
        guard
            let lut = mirror.descendant("_$backingData", "_storage", "lut", "backing")
            as? [String: Int],
            let values = mirror.descendant("_$backingData", "_storage", "arr") as? [Any?]
        else {
            return [:]
        }

        var result: [String: Any] = [:]
        for (name, index) in lut where values.indices.contains(index) {
            if let value = values[index] {
                result[name] = value
            }
        }
        return result
    }
}

extension ModelContext {
    /// The number of persisted rows of `type`, opening the existential metatype
    /// so the generic `fetchCount` can infer its `PersistentModel`.
    func inspectorCount(of type: any PersistentModel.Type) -> Int {
        func open<T: PersistentModel>(_: T.Type) -> Int {
            (try? fetchCount(FetchDescriptor<T>())) ?? 0
        }
        return open(type)
    }

    /// Up to `limit` persisted rows of `type` as type-erased models, opening the
    /// existential metatype so the generic `fetch` can infer its
    /// `PersistentModel`. A `nil` limit fetches every row.
    func inspectorFetch(_ type: any PersistentModel.Type, limit: Int?) -> [any PersistentModel] {
        func open<T: PersistentModel>(_: T.Type) -> [any PersistentModel] {
            var descriptor = FetchDescriptor<T>()
            if let limit {
                descriptor.fetchLimit = limit
            }
            return (try? fetch(descriptor)) ?? []
        }
        return open(type)
    }
}
