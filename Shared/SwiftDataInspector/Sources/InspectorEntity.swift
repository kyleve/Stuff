import Foundation
import SwiftData

/// A single SwiftData entity (one `@Model` type) as the inspector lists it.
///
/// `Sendable` so it can be produced on the background reader actor and handed
/// back to it when loading rows. The only non-value field is `type`, a metatype,
/// which is safe to share across actors.
///
/// `Hashable` so it (and the routes that wrap it) can drive value-based
/// navigation. Identity is the schema-level shape — name, concrete type, and
/// column structure — deliberately excluding the live `count`, so a row-count
/// change doesn't make an already-pushed route look like a different entity.
struct InspectorEntity: Identifiable, Hashable {
    /// The entity / model name (e.g. "SDEvidence"). Drives the row title and the
    /// list's stable identity.
    let name: String
    /// The concrete model type, used to fetch the entity's rows and count.
    let type: any PersistentModel.Type
    /// Number of persisted rows.
    let count: Int
    /// Ordered column names (attributes, then relationships) for the detail
    /// table's headers.
    let columns: [String]
    /// Columns whose attribute type is `Data` / `Data?`. Rendered as a size or a
    /// placeholder so external-storage blobs are never materialized just to
    /// display them.
    let binaryColumns: Set<String>
    /// Columns that model a relationship. Rendered as a placeholder so the
    /// related object graph is never faulted in just to display a row.
    let relationshipColumns: Set<String>

    var id: String {
        name
    }

    static func == (lhs: InspectorEntity, rhs: InspectorEntity) -> Bool {
        lhs.name == rhs.name
            && ObjectIdentifier(lhs.type) == ObjectIdentifier(rhs.type)
            && lhs.columns == rhs.columns
            && lhs.binaryColumns == rhs.binaryColumns
            && lhs.relationshipColumns == rhs.relationshipColumns
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(ObjectIdentifier(type))
        hasher.combine(columns)
        hasher.combine(binaryColumns)
        hasher.combine(relationshipColumns)
    }
}
