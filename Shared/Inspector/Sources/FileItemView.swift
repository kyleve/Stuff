import SFSafeSymbols
import SwiftUI

struct FileItemView<Destination: View>: View {
    let item: InspectorFileItem
    let destination: () -> Destination
    let onDelete: () async -> Void

    @State private var isConfirmingDeletion = false

    var body: some View {
        NavigationLink(destination: destination) {
            Label {
                FileItemDescription(item: item)
            } icon: {
                Image(systemSymbol: item.isSymbolicLink
                    ? .link
                    : item.isDirectory ? .folder : .doc)
            }
        }
        .swipeActions {
            if item.deletionProhibition == nil {
                Button("Delete", systemSymbol: .trash, role: .destructive) {
                    isConfirmingDeletion = true
                }
            }
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible,
        ) {
            Button("Delete", role: .destructive) {
                Task { await onDelete() }
            }
        } message: {
            Text(item.isDirectory
                ? "The folder and everything inside it will be deleted."
                : "The file will be deleted.")
        }
    }
}

private struct FileItemDescription: View {
    let item: InspectorFileItem

    var body: some View {
        VStack(alignment: .leading) {
            Text(item.name)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let deletionProhibition = item.deletionProhibition {
                Label(deletionProhibition, systemSymbol: .lock)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var detail: String? {
        if item.isDirectory {
            if item.isSymbolicLink {
                return item.isHidden ? "Hidden symbolic link" : "Symbolic link"
            }
            return item.isHidden ? "Hidden folder" : nil
        }
        if let byteCount = item.byteCount {
            return ByteCountFormatStyle(style: .file).format(Int64(byteCount))
        }
        return item.isHidden ? "Hidden file" : nil
    }
}

#if DEBUG
    #Preview {
        InspectorFilesPreview()
    }
#endif
