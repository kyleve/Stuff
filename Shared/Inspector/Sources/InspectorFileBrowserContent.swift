import SFSafeSymbols
import SwiftUI

struct InspectorFileBrowserContent: View {
    let isEmpty: Bool
    let items: [InspectorFileItem]
    let container: InspectorConfiguration.FileContainer
    let fileSystem: InspectorFileSystem
    let preview: (InspectorFileItem) async -> Void
    let delete: (InspectorFileItem) async -> Void

    var body: some View {
        if isEmpty {
            ContentUnavailableView(
                "Empty Folder",
                systemSymbol: .folder,
                description: Text("This folder contains no files."),
            )
        } else if items.isEmpty {
            ContentUnavailableView.search
        } else {
            List(items) { item in
                FileItemView(
                    item: item,
                    destination: {
                        InspectorFileDestination(
                            item: item,
                            container: container,
                            fileSystem: fileSystem,
                            preview: preview,
                        )
                    },
                    onDelete: { await delete(item) },
                )
            }
        }
    }
}

private struct InspectorFileDestination: View {
    let item: InspectorFileItem
    let container: InspectorConfiguration.FileContainer
    let fileSystem: InspectorFileSystem
    let preview: (InspectorFileItem) async -> Void

    var body: some View {
        if item.isDirectory, !item.isSymbolicLink {
            AnyView(InspectorFileBrowserView(
                container: container,
                directory: item.url,
                fileSystem: fileSystem,
            ))
        } else {
            AnyView(InspectorFileDetailView(item: item) {
                await preview(item)
            })
        }
    }
}

private struct InspectorFileDetailView: View {
    let item: InspectorFileItem
    let preview: () async -> Void

    var body: some View {
        Form {
            InspectorFileMetadata(item: item)
            Button("Preview File", systemSymbol: .eye) {
                Task { await preview() }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InspectorFileMetadata: View {
    let item: InspectorFileItem

    var body: some View {
        Section("File") {
            LabeledContent("Name", value: item.name)
            LabeledContent("Path", value: item.url.path(percentEncoded: false))
            if let byteCount = item.byteCount {
                LabeledContent(
                    "Size",
                    value: ByteCountFormatStyle(style: .file).format(Int64(byteCount)),
                )
            }
            if let modificationDate = item.modificationDate {
                LabeledContent(
                    "Modified",
                    value: modificationDate.formatted(date: .abbreviated, time: .standard),
                )
            }
        }
    }
}

#if DEBUG
    #Preview {
        InspectorFilesPreview()
    }
#endif
