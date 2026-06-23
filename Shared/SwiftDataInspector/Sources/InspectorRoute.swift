import Foundation
import SwiftData
import SwiftUI

// The destinations the inspector pushes onto the ambient `NavigationStack`,
// expressed as `Hashable` values rather than inline `navigationDestination`s.
//
// Drilling in is recursive (a row → its relationship → a related row → *its*
// relationship → …), and declaring a `navigationDestination(item:)` per level
// re-registers the same destination type repeatedly down one stack, which
// SwiftUI warns about and resolves ambiguously. Instead every push is a
// `NavigationLink(value:)` of one of these routes, and `SwiftDataInspectorView`
// registers each route's destination exactly once at the root — so the same
// route type can recur to any depth from a single declaration. The entity-table
// drill-in needs no wrapper — `InspectorEntity` is itself `Hashable` and routes
// directly.

/// A drill-in to a single row's full detail.
struct InspectorRowRoute: Hashable {
    /// The entity the row belongs to (its columns drive the detail layout).
    let entity: InspectorEntity
    /// The row to show in full.
    let row: InspectorRow
}

/// A drill-in to one relationship of a row, resolved on demand.
struct InspectorRelationshipRoute: Hashable {
    /// The entity owning the relationship (its `type` re-fetches the source row).
    let sourceEntity: InspectorEntity
    /// The persistent id of the row whose relationship is being resolved.
    let sourceRowID: PersistentIdentifier
    /// The relationship property name to resolve.
    let relationshipName: String
}

extension View {
    /// Register the inspector's three drill-in destinations on the ambient
    /// `NavigationStack`. Apply once near the root: every deeper view pushes by
    /// appending a route value, so the recursive routes all resolve from this one
    /// declaration instead of a `navigationDestination(item:)` per level.
    func inspectorNavigationDestinations(model: SwiftDataInspectorModel) -> some View {
        navigationDestination(for: InspectorEntity.self) { entity in
            EntityTableView(model: model, entity: entity)
        }
        .navigationDestination(for: InspectorRowRoute.self) { route in
            RowDetailView(model: model, entity: route.entity, row: route.row)
        }
        .navigationDestination(for: InspectorRelationshipRoute.self) { route in
            RelationshipView(
                model: model,
                sourceEntity: route.sourceEntity,
                sourceRowID: route.sourceRowID,
                relationshipName: route.relationshipName,
            )
        }
    }
}
