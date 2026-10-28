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

    /// The destination model type named by a relationship on `sourceType`, read
    /// from the public schema. Used when a resolved relationship value is a bare
    /// `PersistentIdentifier` (to-one) or a collection of identifiers (to-many)
    /// so the reader can still batch-fetch the related rows.
    static func destinationType(
        of sourceType: any PersistentModel.Type,
        relationshipNamed name: String,
        in schema: Schema,
    ) -> (any PersistentModel.Type)? {
        let sourceName = String(describing: sourceType)
        guard
            let sourceEntity = schema.entities.first(where: { $0.name == sourceName }),
            let relationship = sourceEntity.relationshipsByName[name],
            let destinationEntity = schema.entities
            .first(where: { $0.name == relationship.destination })
        else {
            return nil
        }
        return metatype(of: destinationEntity)
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
        schema: Schema,
    ) -> RelatedReferences {
        /// The generic parameter implicitly opens the `any PersistentModel`
        /// existential, so `schemaMetadata` and `[keyPath:]` resolve concretely.
        func open<T: PersistentModel>(_ model: T) -> RelatedReferences {
            let fallbackDestination = destinationType(
                of: T.self,
                relationshipNamed: name,
                in: schema,
            )
            for property in T.schemaMetadata {
                let mirror = Mirror(reflecting: property)
                guard mirror.descendant("name") as? String == name else { continue }
                guard let keyPath = mirror.descendant("keypath") as? PartialKeyPath<T> else {
                    continue
                }
                return classify(
                    model[keyPath: keyPath],
                    fallbackDestinationType: fallbackDestination,
                )
            }
            return .none
        }
        return open(model)
    }

    /// Classify a resolved relationship value into identifiers, arity, and the
    /// destination model type. Handles a lone reference (to-one), a Swift
    /// `Array`, and any other collection/set (via `Mirror`), unwrapping optionals
    /// along the way. When the value is a bare `PersistentIdentifier`, falls
    /// back to `fallbackDestinationType` from schema metadata.
    private static func classify(
        _ value: Any,
        fallbackDestinationType: (any PersistentModel.Type)?,
    ) -> RelatedReferences {
        guard let unwrapped = InspectorOptionalUnwrapping.unwrap(value) else {
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
            return RelatedReferences(
                ids: [id],
                isToMany: false,
                destinationType: fallbackDestinationType,
            )
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
            .compactMap { InspectorOptionalUnwrapping.unwrap($0) as? any PersistentModel }
            .first
            .map { type(of: $0) }
            ?? fallbackDestinationType
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
        guard let unwrapped = InspectorOptionalUnwrapping.unwrap(value) else { return nil }
        if let model = unwrapped as? any PersistentModel {
            return model.persistentModelID
        }
        if let id = unwrapped as? PersistentIdentifier {
            return id
        }
        return nil
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
