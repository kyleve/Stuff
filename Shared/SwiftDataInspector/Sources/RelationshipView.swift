import SwiftData
import SwiftUI

/// The related rows behind one relationship, resolved on demand (off the main
/// thread) when the user drills into it from `RowDetailView`.
///
/// A to-one relationship drills straight into the single related row's detail; a
/// to-many lists the related rows, each of which drills into its own detail —
/// so a graph can be browsed to any depth. An empty or unreadable relationship
/// shows an empty state.
struct RelationshipView: View {
    let model: SwiftDataInspectorModel
    let sourceEntity: InspectorEntity
    let sourceRowID: PersistentIdentifier
    let relationshipName: String

    @State private var related: InspectorRelatedRows?
    @State private var selectedRow: InspectorRow?

    var body: some View {
        Group {
            if let related {
                content(for: related)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(relationshipName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        related = await model.relatedRows(
            of: sourceRowID,
            relationship: relationshipName,
            sourceType: sourceEntity.type,
        )
    }

    @ViewBuilder
    private func content(for related: InspectorRelatedRows) -> some View {
        if let entity = related.entity, let first = related.rows.first {
            if related.isToMany {
                List {
                    Section(sectionTitle(for: related)) {
                        ForEach(related.rows) { row in
                            Button {
                                selectedRow = row
                            } label: {
                                RelatedRowLabel(entity: entity, row: row)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                .navigationDestination(item: $selectedRow) { row in
                    RowDetailView(model: model, entity: entity, row: row)
                }
            } else {
                // To-one: skip the intermediate list and show the related row.
                RowDetailView(model: model, entity: entity, row: first)
            }
        } else {
            ContentUnavailableView(
                "No Related Rows",
                systemImage: "tray",
                description: Text("This relationship is empty."),
            )
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

/// A related row in a to-many list: the destination entity name plus a
/// best-effort one-line summary (its first non-empty attribute value).
private struct RelatedRowLabel: View {
    let entity: InspectorEntity
    let row: InspectorRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.name)
                    .font(.callout)
                if let summary {
                    Text(summary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
    }

    private var summary: String? {
        for column in entity.columns where !entity.relationshipColumns.contains(column) {
            if let value = row.cells[column], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

#if DEBUG
    #Preview {
        InspectorPreviewData.relationshipPreview()
    }
#endif
