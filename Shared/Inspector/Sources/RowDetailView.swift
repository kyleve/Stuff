import SFSafeSymbols
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
            if !attributeColumns.isEmpty {
                Section("Attributes") {
                    ForEach(attributeColumns, id: \.self) { column in
                        AttributeRow(label: column, value: row.cells[column])
                    }
                }
            }
            if !relationshipColumns.isEmpty {
                Section("Relationships") {
                    ForEach(relationshipColumns, id: \.self) { column in
                        Button {
                            selectedRelationship = column
                        } label: {
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
            }
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
                Button("Delete Row", systemSymbol: .trash, role: .destructive) {
                    isConfirmingDeletion = true
                }
                .confirmationDialog(
                    "Delete this \(entity.name) row?",
                    isPresented: $isConfirmingDeletion,
                    titleVisibility: .visible,
                ) {
                    Button("Delete Row", role: .destructive) {
                        Task {
                            if await model.delete(rowID: row.persistentID, from: entity) {
                                dismiss()
                            }
                        }
                    }
                } message: {
                    Text(
                        "SwiftData relationship delete rules will be applied. This cannot be undone.",
                    )
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

#if DEBUG
    #Preview {
        InspectorPreviewData.rowDetailPreview()
    }
#endif
