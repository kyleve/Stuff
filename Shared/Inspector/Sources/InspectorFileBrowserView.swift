import QuickLook
import SFSafeSymbols
import SwiftUI

struct InspectorFileBrowserView: View {
    fileprivate enum SortOrder: String, CaseIterable {
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
                InspectorFileBrowserContent(
                    isEmpty: items.isEmpty,
                    items: sortedItems,
                    container: container,
                    fileSystem: fileSystem,
                    preview: preview,
                    delete: delete,
                )
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
                InspectorFileSortMenu(sortOrder: $sortOrder, isAscending: $isSortAscending)
            }
        }
        .alert("File Operation Failed", isPresented: $isPresentingError) {} message: {
            Text(errorMessage ?? "The operation failed.")
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

    private func preview(_ item: InspectorFileItem) async {
        do {
            previewURL = try await fileSystem.previewURL(for: item, in: container)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
            isPresentingError = true
        }
    }
}

private struct InspectorFileSortMenu: View {
    @Binding var sortOrder: InspectorFileBrowserView.SortOrder
    @Binding var isAscending: Bool

    var body: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(InspectorFileBrowserView.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            Toggle("Ascending", isOn: $isAscending)
        } label: {
            Label("Sort", systemSymbol: .arrowUpArrowDown)
        }
    }
}
