import Foundation
import SwiftData

/// A single SwiftData entity (one `@Model` type) as the inspector lists it.
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

    var id: String {
        name
    }
}
