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

    /// The related rows referenced by a model's relationship `name`, as
    /// `PersistentIdentifier`s plus whether the relationship is to-many.
    ///
    /// Unlike an attribute (read straight from the backing slot), a relationship
    /// slot holds an *unresolved future* until its property getter runs. So this
    /// opens the model's concrete type, finds the relationship's key path in
    /// `schemaMetadata`, and reads `model[keyPath:]` — which runs the getter and
    /// faults the related objects in. That fault is the entire point of the
    /// detail drill-in, and the *only* place the inspector resolves a
    /// relationship; the table never does. Degrades to no references (rather than
    /// trapping) if the metadata shape is not what we expect.
    static func relatedReferences(
        of model: any PersistentModel,
        named name: String,
    ) -> RelatedReferences {
        /// The generic parameter implicitly opens the `any PersistentModel`
        /// existential, so `schemaMetadata` and `[keyPath:]` resolve concretely.
        func open<T: PersistentModel>(_ model: T) -> RelatedReferences {
            for property in T.schemaMetadata {
                let mirror = Mirror(reflecting: property)
                guard mirror.descendant("name") as? String == name else { continue }
                guard let keyPath = mirror.descendant("keypath") as? PartialKeyPath<T> else {
                    return .none
                }
                return classify(model[keyPath: keyPath])
            }
            return .none
        }
        return open(model)
    }

    /// Classify a resolved relationship value into identifiers, arity, and the
    /// destination model type. Handles a lone reference (to-one), a Swift
    /// `Array`, and any other collection/set (via `Mirror`), unwrapping optionals
    /// along the way. The destination type comes from a resolved related model so
    /// the reader can re-fetch each row fully materialized.
    private static func classify(_ value: Any) -> RelatedReferences {
        guard let unwrapped = unwrapOptional(value) else {
            return .none
        }
        if let model = unwrapped as? any PersistentModel {
            return RelatedReferences(
                ids: [model.persistentModelID],
                isToMany: false,
                destinationType: type(of: model),
            )
        }
        if let id = unwrapped as? PersistentIdentifier {
            return RelatedReferences(ids: [id], isToMany: false, destinationType: nil)
        }

        let elements: [Any]
        if let array = unwrapped as? [Any] {
            elements = array
        } else {
            let mirror = Mirror(reflecting: unwrapped)
            guard mirror.displayStyle == .collection || mirror.displayStyle == .set else {
                return .none
            }
            elements = mirror.children.map(\.value)
        }
        let destinationType = elements
            .lazy
            .compactMap { unwrapOptional($0) as? any PersistentModel }
            .first
            .map { type(of: $0) }
        return RelatedReferences(
            ids: elements.compactMap(identifier(from:)),
            isToMany: true,
            destinationType: destinationType,
        )
    }

    /// The `PersistentIdentifier` for a relationship element, whether the slot
    /// stored the related model itself or just its identifier. Unwraps optionals
    /// so an `Optional(model)` element still resolves.
    private static func identifier(from value: Any) -> PersistentIdentifier? {
        guard let unwrapped = unwrapOptional(value) else { return nil }
        if let model = unwrapped as? any PersistentModel {
            return model.persistentModelID
        }
        if let id = unwrapped as? PersistentIdentifier {
            return id
        }
        return nil
    }

    /// Strip any nesting of `Optional`, yielding the inner value or `nil` at
    /// `.none`.
    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        guard let child = mirror.children.first else { return nil }
        return unwrapOptional(child.value)
    }
}

/// The related rows a relationship points at: their persistent identifiers,
/// whether the relationship is to-many (so the UI lists them) or to-one (so it
/// drills straight in), and the destination model type (so each row can be
/// re-fetched fully materialized). `destinationType` is `nil` when nothing
/// resolved (an empty relationship).
struct RelatedReferences {
    let ids: [PersistentIdentifier]
    let isToMany: Bool
    let destinationType: (any PersistentModel.Type)?

    /// Nothing resolved — an empty, missing, or unreadable relationship.
    static let none = RelatedReferences(ids: [], isToMany: false, destinationType: nil)
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

    /// The persisted row of `type` with `id`, or `nil` if it is no longer in the
    /// store. Uses a `persistentModelID` predicate (not `model(for:)`, which
    /// traps on a missing id) so a row deleted between loading the table and
    /// drilling into it degrades gracefully. Opens the existential so the generic
    /// `fetch` can infer its `PersistentModel`.
    func inspectorModel(
        _ type: any PersistentModel.Type,
        id: PersistentIdentifier,
    ) -> (any PersistentModel)? {
        func open<T: PersistentModel>(_: T.Type) -> (any PersistentModel)? {
            var descriptor =
                FetchDescriptor<T>(predicate: #Predicate { $0.persistentModelID == id })
            descriptor.fetchLimit = 1
            return (try? fetch(descriptor))?.first
        }
        return open(type)
    }

    /// Up to `limit` persisted rows of `type` starting at `offset`, as type-erased
    /// models, opening the existential metatype so the generic `fetch` can infer
    /// its `PersistentModel`. A `nil` limit fetches every row from `offset` on;
    /// `offset` drives the inspector's "load more" pagination via `fetchOffset`.
    func inspectorFetch(
        _ type: any PersistentModel.Type,
        limit: Int?,
        offset: Int = 0,
    ) -> [any PersistentModel] {
        func open<T: PersistentModel>(_: T.Type) -> [any PersistentModel] {
            var descriptor = FetchDescriptor<T>()
            if let limit {
                descriptor.fetchLimit = limit
            }
            descriptor.fetchOffset = offset
            return (try? fetch(descriptor)) ?? []
        }
        return open(type)
    }
}
