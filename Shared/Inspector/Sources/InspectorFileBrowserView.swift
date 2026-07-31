import QuickLook
import SwiftUI

struct InspectorFileBrowserView: View {
    private enum SortOrder: String, CaseIterable {
        case name = "Name"
        case modificationDate = "Modified"
        case size = "Size"
    }

    let container: InspectorConfiguration.FileContainer
    let directory: URL
    let fileSystem: InspectorFileSystem

    @State private var items: [InspectorFileItem] = []
    @State private var searchText = ""
    @State private var previewURL: URL?
    @State private var sortOrder = SortOrder.name
    @State private var isSortAscending = true
    @State private var errorMessage: String?
    @State private var isPresentingError = false
    @State private var hasLoaded = false

    init(
        container: InspectorConfiguration.FileContainer,
        directory: URL? = nil,
        fileSystem: InspectorFileSystem,
    ) {
        self.container = container
        self.directory = directory ?? container.rootURL
        self.fileSystem = fileSystem
    }

    var body: some View {
        Group {
            if hasLoaded {
                content
            } else {
                ProgressView()
            }
        }
        .navigationTitle(directory == container.rootURL ? container.title : directory
            .lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search files")
        .task(id: ObjectIdentifier(fileSystem)) { await load() }
        .refreshable { await load() }
        .quickLookPreview($previewURL)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Sort", systemImage: "arrow.up.arrow.down") {
                    Picker("Sort by", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    Toggle("Ascending", isOn: $isSortAscending)
                }
            }
        }
        .alert("File Operation Failed", isPresented: $isPresentingError) {} message: {
            Text(errorMessage ?? "The operation failed.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "Empty Folder",
                systemImage: "folder",
                description: Text("This folder contains no files."),
            )
        } else if filteredItems.isEmpty {
            ContentUnavailableView.search
        } else {
            List(sortedItems) { item in
                FileItemView(
                    item: item,
                    destination: {
                        if item.isDirectory, !item.isSymbolicLink {
                            AnyView(InspectorFileBrowserView(
                                container: container,
                                directory: item.url,
                                fileSystem: fileSystem,
                            ))
                        } else {
                            AnyView(InspectorFileDetailView(item: item) {
                                previewURL = item.url
                            })
                        }
                    },
                    onDelete: { await delete(item) },
                )
            }
        }
    }

    private var filteredItems: [InspectorFileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var sortedItems: [InspectorFileItem] {
        filteredItems.sorted { left, right in
            if left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            let comparison: ComparisonResult = switch sortOrder {
                case .name:
                    left.name.localizedStandardCompare(right.name)
                case .modificationDate:
                    compare(left.modificationDate, right.modificationDate)
                case .size:
                    compare(left.byteCount, right.byteCount)
            }
            if comparison == .orderedSame {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return isSortAscending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private func compare<T: Comparable>(_ left: T?, _ right: T?) -> ComparisonResult {
        switch (left, right) {
            case let (left?, right?) where left < right: .orderedAscending
            case let (left?, right?) where left > right: .orderedDescending
            case (nil, .some): .orderedAscending
            case (.some, nil): .orderedDescending
            default: .orderedSame
        }
    }

    private func load() async {
        do {
            items = try await fileSystem.contents(of: directory, in: container)
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            isPresentingError = true
            hasLoaded = true
        }
    }

    private func delete(_ item: InspectorFileItem) async {
        do {
            try await fileSystem.delete(item, in: container)
            await load()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            isPresentingError = true
        }
    }
}

private struct FileItemView: View {
    let item: InspectorFileItem
    let destination: () -> AnyView
    let onDelete: () async -> Void

    @State private var isConfirmingDeletion = false

    var body: some View {
        NavigationLink(destination: destination) {
            Label {
                VStack(alignment: .leading) {
                    Text(item.name)
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let deletionProhibition = item.deletionProhibition {
                        Label(deletionProhibition, systemImage: "lock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } icon: {
                Image(systemName: item.isSymbolicLink
                    ? "link"
                    : item.isDirectory ? "folder" : "doc")
            }
        }
        .swipeActions {
            if item.deletionProhibition == nil {
                Button("Delete", systemImage: "trash", role: .destructive) {
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

private struct InspectorFileDetailView: View {
    let item: InspectorFileItem
    let preview: () -> Void

    var body: some View {
        Form {
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
            Button("Preview File", systemImage: "eye", action: preview)
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
