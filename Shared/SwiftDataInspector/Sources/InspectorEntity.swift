import Foundation
import SwiftData

/// A single SwiftData entity (one `@Model` type) as the inspector lists it.
///
/// `Sendable` so it can be produced on the background reader actor and handed
/// back to it when loading rows. The only non-value field is `type`, a metatype,
/// which is safe to share across actors.
struct InspectorEntity: Identifiable {
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
}
