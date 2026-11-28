import SFSafeSymbols
import SwiftUI

/// A related row in a to-many list: the destination entity name plus a
/// best-effort one-line summary (its first non-empty attribute value).
struct RelatedRowButton: View {
    let entity: InspectorEntity
    let row: InspectorRow
    let select: () -> Void

    var body: some View {
        Button(action: select) {
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
                Image(systemSymbol: .chevronRight)
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
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
    #Preview { InspectorPreviewData.relationshipPreview() }
#endif
