import SFSafeSymbols
import SwiftData
import SwiftUI

/// The full detail of a single row: every attribute with its complete,
/// selectable value, plus a tappable entry for each relationship that drills
/// into the related rows.
///
/// Attribute values are the ones already loaded into `row.cells` (full strings —
/// the table only truncated them visually), so showing them costs no extra
/// fetch. Relationships are deliberately *not* resolved here; tapping one pushes
/// a `RelationshipView` that resolves it on demand, preserving the rule that
/// nothing is faulted in just to draw a screen.
struct RowDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let model: InspectorSwiftDataModel
    let entity: InspectorEntity
    let row: InspectorRow

    @State private var selectedRelationship: String?
    @State private var isConfirmingDeletion = false

    var body: some View {
        List {
            RowAttributesSection(columns: attributeColumns, row: row)
            RowRelationshipsSection(columns: relationshipColumns) { selectedRelationship = $0 }
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRelationship) { name in
            RelationshipView(
                model: model,
                sourceEntity: entity,
                sourceRowID: row.persistentID,
                relationshipName: name,
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InspectorDeleteButton(
                    title: "Delete Row",
                    symbol: .trash,
                    question: "Delete this \(entity.name) row?",
                    message: "SwiftData relationship delete rules will be applied. This cannot be undone.",
                    isConfirming: $isConfirmingDeletion,
                ) {
                    Task {
                        if await model.delete(rowID: row.persistentID, from: entity) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var attributeColumns: [String] {
        entity.columns.filter { !entity.relationshipColumns.contains($0) }
    }

    private var relationshipColumns: [String] {
        entity.columns.filter { entity.relationshipColumns.contains($0) }
    }
}

/// One attribute as a label over its full value. A column with no stored value
/// renders a muted placeholder rather than nothing, matching the table.
private struct AttributeRow: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
        .padding(.vertical, 2)
    }
}

private struct RowAttributesSection: View {
    let columns: [String]
    let row: InspectorRow

    var body: some View {
        if !columns.isEmpty {
            Section("Attributes") {
                ForEach(columns, id: \.self) { column in
                    AttributeRow(label: column, value: row.cells[column])
                }
            }
        }
    }
}

private struct RowRelationshipsSection: View {
    let columns: [String]
    let select: (String) -> Void

    var body: some View {
        if !columns.isEmpty {
            Section("Relationships") {
                ForEach(columns, id: \.self) { column in
                    RelationshipButton(column: column) { select(column) }
                }
            }
        }
    }
}

private struct RelationshipButton: View {
    let column: String
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack {
                Text(column)
                Spacer()
                Image(systemSymbol: .chevronRight)
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
    }
}

/// The related rows behind one relationship, resolved on demand (off the main
/// thread) when the user drills into it from `RowDetailView`.
///
/// A to-one relationship drills straight into the single related row's detail; a
/// to-many lists the related rows, each of which drills into its own detail —
/// so a graph can be browsed to any depth. Successful mutations re-resolve the
/// relationship before presenting its rows again. An empty or unreadable
/// relationship shows an empty state.
struct RelationshipView: View {
    let model: InspectorSwiftDataModel
    let sourceEntity: InspectorEntity
    let sourceRowID: PersistentIdentifier
    let relationshipName: String

    @State private var related: InspectorRelatedRows?
    @State private var selectedRow: InspectorRow?

    var body: some View {
        Group {
            if let related {
                RelationshipContent(model: model, related: related, selectedRow: $selectedRow)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(relationshipName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.mutationTrigger) { await load() }
    }

    private func load() async {
        do {
            related = try await model.relatedRows(
                of: sourceRowID,
                relationship: relationshipName,
                sourceType: sourceEntity.type,
            )
        } catch is CancellationError {
            return
        } catch {
            model.report(error)
        }
    }
}

private struct RelationshipContent: View {
    let model: InspectorSwiftDataModel
    let related: InspectorRelatedRows
    @Binding var selectedRow: InspectorRow?

    var body: some View {
        if let entity = related.entity, let first = related.rows.first {
            if related.isToMany {
                RelatedRowsList(
                    model: model,
                    entity: entity,
                    related: related,
                    selectedRow: $selectedRow,
                )
            } else {
                // To-one: skip the intermediate list and show the related row.
                RowDetailView(model: model, entity: entity, row: first)
            }
        } else {
            ContentUnavailableView(
                "No Related Rows",
                systemSymbol: .tray,
                description: Text("This relationship is empty."),
            )
        }
    }
}

private struct RelatedRowsList: View {
    let model: InspectorSwiftDataModel
    let entity: InspectorEntity
    let related: InspectorRelatedRows
    @Binding var selectedRow: InspectorRow?

    var body: some View {
        List {
            Section(sectionTitle(for: related)) {
                ForEach(related.rows) { row in
                    RelatedRowButton(entity: entity, row: row) { selectedRow = row }
                }
            }
        }
        .navigationDestination(item: $selectedRow) { row in
            RowDetailView(model: model, entity: entity, row: row)
        }
    }

    /// The to-many section header: the related count, noting when only the first
    /// `rowLimit` of a larger relationship were materialized.
    private func sectionTitle(for related: InspectorRelatedRows) -> String {
        if related.rows.count < related.totalCount {
            "Showing \(related.rows.count) of \(related.totalCount) related"
        } else {
            "\(related.rows.count) related"
        }
    }
}

#if DEBUG
    #Preview {
        InspectorPreviewData.rowDetailPreview()
    }
#endif
