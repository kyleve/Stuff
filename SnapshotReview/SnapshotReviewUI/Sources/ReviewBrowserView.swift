import BroadwayUI
import SFSafeSymbols
import SnapshotReviewCore
import SwiftUI
import UniformTypeIdentifiers

public struct ReviewBrowserView: View {
    @Bindable private var model: ReviewBrowserModel
    @State private var loader = ReviewImageLoader()
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase

    public init(model: ReviewBrowserModel) {
        self.model = model
    }

    public var body: some View {
        ReviewBrowserContent(model: model, loader: loader)
            .broadwayRoot()
            .fileImporter(
                isPresented: $model.isImporting,
                allowedContentTypes: [.folder],
            ) { result in
                switch result {
                    case let .success(url): Task { await model.open(url) }
                    case let .failure(error): model.error = error
                }
            }
            .sheet(item: $model.draft) { draft in
                ReviewAnnotationEditor(model: model, draft: draft)
            }
            .task { model.undoManager = undoManager; await model.restore() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, model.draft == nil { Task { await model.refresh() } }
            }
    }
}

struct ReviewBrowserContent: View {
    @Bindable var model: ReviewBrowserModel
    let loader: any ReviewImageLoading
    @Environment(\.reviewStyle) private var style
    @State private var visibility = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
            VStack(spacing: 0) {
                TextField("Search snapshots", text: $model.search).textFieldStyle(.roundedBorder)
                    .padding()
                Picker("Filter", selection: $model.filter) {
                    ForEach(ReviewFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.padding(.horizontal)
                List {
                    ForEach(model.cases) { group in
                        Button { model.select(.group(group.id)) } label: {
                            VStack(alignment: .leading) {
                                Text(group.id.suite.lastPathComponent).font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(group.label)
                                Text(model.countLabel(group.id)).font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(model.selectedCase == group.id ? Color.accentColor
                            .opacity(style.browser.selectionOpacity) : nil)
                    }
                }
                .frame(maxHeight: model.isSingleImage ? style.browser
                    .caseListMaximumHeight : .infinity)
                if let image = model.selectedImage {
                    Divider()
                    ReviewDetailsView(model: model, image: image).frame(maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(
                min: style.browser.minimumSidebarWidth,
                ideal: style.browser.sidebarWidth,
            )
        } detail: {
            VStack(spacing: style.browser.gap) {
                if let error = model.error {
                    HStack {
                        Text(error.localizedDescription).foregroundStyle(.red)
                            .textSelection(.enabled)
                        Button("Reload Files") { Task { await model.refresh() }; model.error = nil }
                        Button("Dismiss") { model.error = nil }
                    }
                }
                if let suite = model.suites.first(where: { $0.id == model.selectedCase?.suite }) {
                    if let error = suite
                        .manifestError
                    {
                        Text("Manifest: " + error.localizedDescription).foregroundStyle(.red)
                    }
                    if case let .failure(error) = suite
                        .reviews { Text(error.localizedDescription).foregroundStyle(.red) }
                }
                if model.root != nil {
                    variantControls
                    if model.selectedCase?.caseName == nil {
                        Text(
                            "Run this suite’s snapshot tests to enable exact case grouping and appearance controls.",
                        )
                        .foregroundStyle(.secondary)
                    }
                    if model.isSingleImage {
                        if let image = model.selectedImage { ReviewImageView(
                            image: image,
                            loader: loader,
                            thumbnail: false,
                            model: model,
                        ) } else { unavailable(
                            "Variant unavailable",
                            "This case has no matching image for the selected device and appearance.",
                        ) }
                    } else {
                        grid
                    }
                } else {
                    switch model.state {
                        case .closed: unavailable(
                                "Open Snapshot Folder",
                                "Choose a checkout or a folder containing __Snapshots__ suites.",
                            )
                        case .loading: ProgressView()
                        case let .failed(error): unavailable(
                                "Folder unavailable",
                                error.localizedDescription,
                            )
                        case .open: EmptyView()
                    }
                }
                if let queue = model.queue {
                    HStack {
                        Button("Back") { model.advance(-1) }.disabled(queue.index == 0)
                        Text("\(queue.reviewed.count) of \(queue.images.count) reviewed" +
                            (queue.current == nil ? " · Queue complete" : ""))
                        Button("Skip") { model.advance(1) }.disabled(queue.current == nil)
                        Button("Review and Next") { Task { await model.reviewAndNext() } }
                            .disabled(!model.canReviewDisplayedImage || queue.current == nil)
                    }
                }
            }
            .padding(style.browser.gap)
            .navigationTitle(model.root?.lastPathComponent ?? "Snapshot Review")
            .toolbar { ReviewToolbar(model: model) }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: model.selection) { _, selection in
            compactColumn = selection == nil ? .sidebar : .detail
        }
        .disabled(model.isBusy)
        .overlay { if model.isBusy { ProgressView("Reading or saving files…").padding().background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: style.browser.cornerRadius),
        ) } }
    }

    private var variantControls: some View {
        HStack {
            Picker("Appearance", selection: $model.appearance) {
                Text("Light").tag(SnapshotVariant.Appearance.light)
                Text("Dark").tag(SnapshotVariant.Appearance.dark)
                Text("Other").tag(SnapshotVariant.Appearance.other)
            }.pickerStyle(.segmented).disabled(model.selectedCase?.caseName == nil)
            if model.appearance == .other {
                Picker("Other configuration", selection: $model.other) {
                    Text("First available").tag(SnapshotVariant?.none)
                    ForEach(model.otherVariants, id: \.self) { Text($0.label).tag(Optional($0)) }
                }
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: style.browser.cellWidth))],
                spacing: style.browser.gap,
            ) {
                ForEach(model.visibleImages) { image in
                    Button { model.select(.image(image.id)) } label: {
                        VStack(alignment: .leading) {
                            ReviewImageView(
                                image: image,
                                loader: loader,
                                thumbnail: true,
                                model: model,
                            ).frame(height: style.browser.thumbnailHeight)
                            Text(image.metadata?.frame ?? image.id.path.value).font(.headline)
                            if let name = image.metadata?.configurationName { Text(name) }
                            Text(model.needsReview(image) ? "Needs review" : "Reviewed")
                                .font(.caption)
                            Text("\(model.review(image)?.openTodoCount ?? 0) open todos")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
                            .background,
                            in: RoundedRectangle(cornerRadius: style.browser.cornerRadius),
                        )
                    }.buttonStyle(.plain)
                }
            }
            if model.visibleImages.isEmpty { unavailable(
                "No matching snapshots",
                "Select another case, appearance, or filter.",
            ) }
        }
    }

    private func unavailable(_ title: String, _ description: String) -> some View {
        ContentUnavailableView { Text(title) } description: { Text(description) }
    }
}

#if DEBUG
    import SnapshotKit

    extension ReviewBrowserView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Empty",
                configurations: [
                    .init(layoutTraits: .tabletPortrait, device: .iPadFullContent),
                    .init(
                        colorScheme: .dark,
                        layoutTraits: .tabletPortrait,
                        device: .iPadFullContent,
                    ),
                ],
                settle: .settledAtLeast(minDuration: 0.3),
            ) {
                ReviewBrowserContent(
                    model: ReviewPreviewFixtures.model(),
                    loader: ReviewImageLoader(),
                ).broadwayRoot()
            }
            loadedCase(name: "Grid", single: false)
        }

        private static func loadedCase(name: String, single: Bool) -> SnapshotCase {
            let loader = ReviewPreviewImageLoader(bitmap: ReviewPreviewFixtures.bitmap())
            return SnapshotCase(
                name: name,
                configurations: [.init(layoutTraits: .tabletPortrait, device: .iPadFullContent)],
                settle: .settledAtLeast(minDuration: 0.3),
                onReadyToSnapshot: { await loader.waitForLoads(single ? 1 : 2) },
            ) {
                ReviewBrowserContent(
                    model: ReviewPreviewFixtures.model(loaded: true, single: single),
                    loader: loader,
                ).broadwayRoot()
            }
        }
    }

    #Preview { ReviewBrowserView.snapshotPreviews }
#endif
