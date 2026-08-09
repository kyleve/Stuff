import PatchlightCore
import SnapshotKit
import SwiftUI
import UIKit

struct PatchlightSnapshotWorkspaceView: View {
    private enum GalleryAxis: String, CaseIterable, Identifiable {
        case vertical
        case horizontal

        var id: Self {
            self
        }
    }

    let files: [DiffFile]
    let model: PatchlightAppModel
    @Environment(\.patchlightStylesheet) private var stylesheet
    @State private var galleryAxis = GalleryAxis.vertical

    var body: some View {
        VStack(spacing: 0) {
            Picker(
                String(localized: "galleryDirection", defaultValue: "Gallery Direction"),
                selection: $galleryAxis,
            ) {
                Label(
                    String(localized: "vertical", defaultValue: "Vertical"),
                    systemImage: "rectangle.split.1x2",
                )
                .tag(GalleryAxis.vertical)
                Label(
                    String(localized: "horizontal", defaultValue: "Horizontal"),
                    systemImage: "rectangle.split.2x1",
                )
                .tag(GalleryAxis.horizontal)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .padding(10)
            if galleryAxis == .vertical {
                HStack(spacing: 0) {
                    verticalGallery.frame(
                        minWidth: stylesheet.sidebar.workspaceWidth.minimum,
                        idealWidth: stylesheet.sidebar.workspaceWidth.ideal,
                        maxWidth: stylesheet.sidebar.workspaceWidth.maximum,
                    )
                    Divider()
                    focusedWorkspace
                }
            } else {
                horizontalGallery.frame(height: 132)
                Divider()
                focusedWorkspace
            }
        }
        .background(.background)
        .task(id: files.first?.path) {
            guard case .none = model.snapshotState, let first = files.first else { return }
            await model.loadSnapshot(first)
        }
    }

    private var verticalGallery: some View {
        List {
            ForEach(groups, id: \.path) { group in
                Section(group.path) {
                    ForEach(group.files) { file in
                        snapshotButton(file)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, stylesheet.sidebar.minimumRowHeight)
        .accessibilityLabel(String(localized: "snapshotGallery", defaultValue: "Snapshot Gallery"))
    }

    private var horizontalGallery: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 20) {
                ForEach(groups, id: \.path) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.path).font(.caption).foregroundStyle(.secondary)
                        LazyHStack {
                            ForEach(group.files) { file in snapshotButton(file) }
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
        .accessibilityLabel(String(localized: "snapshotGallery", defaultValue: "Snapshot Gallery"))
    }

    private func snapshotButton(_ file: DiffFile) -> some View {
        Button {
            Task { await model.loadSnapshot(file) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(URL(fileURLWithPath: file.path).lastPathComponent)
                    .lineLimit(1)
                Text(status(for: file.status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .contentShape(.rect)
        .help(file.path)
    }

    @ViewBuilder
    private var focusedWorkspace: some View {
        switch model.snapshotState {
            case .none:
                ContentUnavailableView(
                    String(localized: "selectSnapshot", defaultValue: "Select a Snapshot"),
                    systemImage: "photo.on.rectangle",
                )
            case let .loading(path):
                ProgressView(
                    String(
                        localized: "loadingSnapshot",
                        defaultValue: "Loading snapshot…",
                    ),
                )
                .accessibilityHint(Text(verbatim: path))
            case let .ready(pair):
                SnapshotComparisonView(pair: pair, model: model)
            case let .failed(path, message):
                ContentUnavailableView(
                    String(
                        localized: "couldNotLoadSnapshot",
                        defaultValue: "Could Not Load Snapshot",
                    ),
                    systemImage: "exclamationmark.triangle",
                    description: Text(String(
                        format: String(
                            localized: "snapshotLoadFailureFormat",
                            defaultValue: "%1$@: %2$@",
                        ),
                        locale: .current,
                        path,
                        message,
                    )),
                )
        }
    }

    private var groups: [SnapshotPathGroup] {
        Dictionary(grouping: files) { file in
            let directory = URL(fileURLWithPath: file.path).deletingLastPathComponent().path
            return directory == "." ? String(localized: "root", defaultValue: "Root") : directory
        }.map { SnapshotPathGroup(path: $0.key, files: $0.value.sorted { $0.path < $1.path }) }
            .sorted { $0.path < $1.path }
    }

    private func status(for status: DiffFileStatus) -> String {
        switch status {
            case .added: String(localized: "added", defaultValue: "Added")
            case .removed: String(localized: "deleted", defaultValue: "Deleted")
            case .renamed: String(localized: "renamed", defaultValue: "Renamed")
            case .modified, .changed: String(localized: "modified", defaultValue: "Modified")
            case .copied: String(localized: "copied", defaultValue: "Copied")
        }
    }
}

private struct SnapshotPathGroup {
    let path: String
    let files: [DiffFile]
}

private struct SnapshotComparisonView: View {
    fileprivate enum Mode: String, CaseIterable, Identifiable {
        case base
        case head
        case sideBySide
        case wipe
        case overlay
        case heatmap

        var id: Self {
            self
        }
    }

    let pair: SnapshotImagePair
    let model: PatchlightAppModel
    @AppStorage(PatchlightAIUserDefaults.globallyEnabled) private var globallyEnabled = false
    @AppStorage(PatchlightAIUserDefaults.provider) private var providerCode = AIProvider.openAI
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.preset) private var presetCode = AnalysisPreset.balanced
        .rawValue
    @AppStorage(PatchlightAIUserDefaults.advancedModelID) private var advancedModelID = ""
    @State private var mode = Mode.sideBySide
    @State private var zoom = 1.0
    @State private var wipe = 0.5
    @State private var opacity = 0.5
    @State private var annotationDraft: SnapshotAnnotationDraft?

    init(
        pair: SnapshotImagePair,
        model: PatchlightAppModel,
        initialMode: Mode = .sideBySide,
        initialAnnotationDraft: SnapshotAnnotationDraft? = nil,
    ) {
        self.pair = pair
        self.model = model
        _mode = State(initialValue: initialMode)
        _annotationDraft = State(initialValue: initialAnnotationDraft)
    }

    private var baseImage: UIImage? {
        pair.base.flatMap { UIImage(data: $0.data) }
    }

    private var headImage: UIImage? {
        pair.head.flatMap { UIImage(data: $0.data) }
    }

    private var heatmapImage: UIImage? {
        guard case let .comparable(_, data) = pair.comparison, let data else { return nil }
        return UIImage(data: data)
    }

    private var hasCompatiblePair: Bool {
        if case .comparable = pair.comparison { true } else { false }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            comparisonNotice
            metrics
            imageAnalysisNotice
            Divider()
            Checkerboard {
                ScrollView([.horizontal, .vertical]) {
                    canvas
                        .scaleEffect(zoom, anchor: .topLeading)
                        .padding(24)
                }
            }
        }
        .background(.background)
        .navigationTitle(pair.file.path)
        .sheet(item: $annotationDraft) { draft in
            SnapshotAnnotationComposer(draft: draft, model: model)
        }
        .onChange(of: pair.file.path) { _, _ in
            mode = pair.base == nil ? .head : pair.head == nil ? .base : .sideBySide
            zoom = 1
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Menu {
                modeButton(
                    .base,
                    title: String(localized: "base", defaultValue: "Base"),
                    disabled: baseImage == nil,
                )
                modeButton(
                    .head,
                    title: String(localized: "head", defaultValue: "Head"),
                    disabled: headImage == nil,
                )
                modeButton(
                    .sideBySide,
                    title: String(localized: "sideBySide", defaultValue: "Side by Side"),
                    disabled: baseImage == nil || headImage == nil,
                )
                modeButton(
                    .wipe,
                    title: String(localized: "wipe", defaultValue: "Wipe"),
                    disabled: !hasCompatiblePair,
                )
                modeButton(
                    .overlay,
                    title: String(localized: "opacityOverlay", defaultValue: "Opacity Overlay"),
                    disabled: !hasCompatiblePair,
                )
                modeButton(
                    .heatmap,
                    title: String(localized: "heatmap", defaultValue: "Heatmap"),
                    disabled: heatmapImage == nil,
                )
            } label: {
                Label(modeTitle, systemImage: "square.3.layers.3d")
            }
            Button(String(localized: "fit", defaultValue: "Fit")) { zoom = 1 }
            Button(String(localized: "oneHundredPercent", defaultValue: "100%")) { zoom = pixelZoom
            }
            Slider(value: $zoom, in: 0.5 ... 4)
                .frame(maxWidth: 180)
                .accessibilityLabel(String(localized: "zoom", defaultValue: "Zoom"))
            if mode == .wipe {
                Slider(value: $wipe, in: 0 ... 1)
                    .frame(maxWidth: 160)
                    .accessibilityLabel(String(
                        localized: "wipePosition",
                        defaultValue: "Wipe Position",
                    ))
            }
            if mode == .overlay {
                Slider(value: $opacity, in: 0 ... 1)
                    .frame(maxWidth: 160)
                    .accessibilityLabel(String(
                        localized: "headOpacity",
                        defaultValue: "Head Opacity",
                    ))
            }
            Spacer()
            Button {
                Task {
                    await model.runImageAnalysis(
                        globallyEnabled: globallyEnabled,
                        provider: selectedProvider,
                        preset: selectedPreset,
                        advancedModelID: advancedModelID,
                    )
                }
            } label: {
                Label(
                    String(localized: "analyzeImages", defaultValue: "Analyze Images"),
                    systemImage: "sparkles.rectangle.stack",
                )
            }
            .disabled(!canRunImageAnalysis || isImageAnalysisRunning)
            Text(pair.file.path).font(.caption).lineLimit(1)
        }
        .padding(10)
        .background(.bar)
    }

    @ViewBuilder
    private var comparisonNotice: some View {
        if case let .dimensionMismatch(base, head) = pair.comparison {
            Label(
                String(
                    format: String(
                        localized: "snapshotDimensionMismatchFormat",
                        defaultValue: "Base is %1$lld×%2$lld; head is %3$lld×%4$lld. Wipe, overlay, and heatmap require matching dimensions.",
                    ),
                    locale: .current,
                    base.width,
                    base.height,
                    head.width,
                    head.height,
                ),
                systemImage: "rectangle.on.rectangle.slash",
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.13))
        }
        if !outdatedAnnotations.isEmpty {
            Label(
                String(
                    format: String(
                        localized: "outdatedSnapshotAnnotationsFormat",
                        defaultValue: "%lld snapshot annotations target older blobs and are shown as outdated, not overlaid.",
                    ),
                    locale: .current,
                    outdatedAnnotations.count,
                ),
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.13))
        }
        if parsedAnnotationState.malformedCount > 0 {
            Label(
                String(
                    format: String(
                        localized: "malformedSnapshotAnnotationsFormat",
                        defaultValue: "%lld snapshot region markers are malformed; their comments remain visible in Conversation.",
                    ),
                    locale: .current,
                    parsedAnnotationState.malformedCount,
                ),
                systemImage: "exclamationmark.bubble",
            )
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.13))
        }
    }

    @ViewBuilder
    private var metrics: some View {
        if case let .comparable(metrics, _) = pair.comparison {
            HStack {
                LabeledContent(
                    String(localized: "changedPixels", defaultValue: "Changed Pixels"),
                    value: metrics.changedPixels.formatted(),
                )
                LabeledContent(
                    String(localized: "changedFraction", defaultValue: "Changed"),
                    value: metrics.changedFraction
                        .formatted(.percent.precision(.fractionLength(2))),
                )
                LabeledContent(
                    String(localized: "maximumDelta", defaultValue: "Maximum Channel Delta"),
                    value: metrics.maximumChannelDelta.formatted(),
                )
            }
            .font(.caption)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var imageAnalysisNotice: some View {
        switch model.imageAnalysisState {
            case .idle:
                if model.repositorySettings?.imageAIEnabled != true {
                    Label(
                        String(
                            localized: "imageAnalysisOff",
                            defaultValue: "Optional image analysis is off for this repository.",
                        ),
                        systemImage: "eye.slash",
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .running:
                HStack {
                    ProgressView()
                    Text(String(
                        localized: "analyzingImages",
                        defaultValue: "Analyzing selected images…",
                    ))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            case let .ready(run):
                VStack(alignment: .leading, spacing: 5) {
                    Label(run.analysis.summary, systemImage: "sparkles")
                    Text("\(providerTitle(run.provider)) / \(run.modelID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(run.analysis.findings) { finding in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(finding.label).font(.headline)
                                Spacer()
                                Text(finding.confidence.formatted(.percent.precision(
                                    .fractionLength(0),
                                )))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                            Text(finding.explanation)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 3)
                    }
                    Text(String(
                        format: String(
                            localized: "imageAnalysisUsageFormat",
                            defaultValue: "%1$lld prompt tokens, %2$lld output tokens, request %3$@",
                        ),
                        locale: .current,
                        run.analysis.usage.promptTokens ?? 0,
                        run.analysis.usage.outputTokens ?? 0,
                        run.analysis.usage.requestID ?? "—",
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.10))
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10))
        }
    }

    @ViewBuilder
    private var canvas: some View {
        switch mode {
            case .base:
                focusedImage(baseImage, target: .base)
            case .head:
                focusedImage(headImage, target: .head)
            case .sideBySide:
                HStack(alignment: .top, spacing: 20) {
                    labeledImage(
                        baseImage,
                        title: String(localized: "base", defaultValue: "Base"),
                        target: .base,
                    )
                    labeledImage(
                        headImage,
                        title: String(localized: "head", defaultValue: "Head"),
                        target: .head,
                    )
                }
            case .wipe:
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        image(baseImage)
                        image(headImage)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: proxy.size.width * wipe)
                            }
                    }
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            case .overlay:
                ZStack {
                    image(baseImage)
                    image(headImage).opacity(opacity)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            case .heatmap:
                image(heatmapImage)
                    .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }

    private func focusedImage(
        _ value: UIImage?,
        target: SnapshotAnnotationTarget,
    ) -> some View {
        GeometryReader { proxy in
            let rect = aspectFitRect(imageSize: value?.size ?? .zero, in: proxy.size)
            ZStack(alignment: .topLeading) {
                image(value)
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                ForEach(matchingAnnotations(target: target), id: \.markerID) { annotation in
                    Rectangle()
                        .stroke(annotation.tag == .problem ? .red : .yellow, lineWidth: 3)
                        .frame(
                            width: rect.width * annotation.rectangle.width,
                            height: rect.height * annotation.rectangle.height,
                        )
                        .offset(
                            x: rect.minX + rect.width * annotation.rectangle.x,
                            y: rect.minY + rect.height * annotation.rectangle.y,
                        )
                }
                ForEach(matchingImageFindings(target: target)) { finding in
                    Rectangle()
                        .stroke(.purple, style: StrokeStyle(lineWidth: 3, dash: [4, 4]))
                        .frame(
                            width: rect.width * finding.rectangle.width,
                            height: rect.height * finding.rectangle.height,
                        )
                        .offset(
                            x: rect.minX + rect.width * finding.rectangle.x,
                            y: rect.minY + rect.height * finding.rectangle.y,
                        )
                        .accessibilityLabel(finding.label)
                        .accessibilityHint(finding.explanation)
                }
                if let draft = annotationDraft, draft.target == target {
                    Rectangle()
                        .stroke(.blue, style: StrokeStyle(lineWidth: 3, dash: [7]))
                        .frame(
                            width: rect.width * draft.rectangle.width,
                            height: rect.height * draft.rectangle.height,
                        )
                        .offset(
                            x: rect.minX + rect.width * draft.rectangle.x,
                            y: rect.minY + rect.height * draft.rectangle.y,
                        )
                }
            }
            .contentShape(.rect)
            .gesture(annotationGesture(rect: rect, target: target, image: value))
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    private func labeledImage(
        _ value: UIImage?,
        title: String,
        target: SnapshotAnnotationTarget,
    ) -> some View {
        VStack {
            Text(title).font(.headline)
            focusedImage(value, target: target)
        }
    }

    private func image(_ value: UIImage?) -> some View {
        Group {
            if let value {
                Image(uiImage: value).resizable().interpolation(.none).scaledToFit()
            } else {
                ContentUnavailableView(
                    String(localized: "imageNotPresent", defaultValue: "Image Not Present"),
                    systemImage: "photo.badge.exclamationmark",
                )
            }
        }
    }

    private func modeButton(_ mode: Mode, title: String, disabled: Bool) -> some View {
        Button(title) { self.mode = mode }.disabled(disabled)
    }

    private var modeTitle: String {
        switch mode {
            case .base: String(localized: "base", defaultValue: "Base")
            case .head: String(localized: "head", defaultValue: "Head")
            case .sideBySide: String(localized: "sideBySide", defaultValue: "Side by Side")
            case .wipe: String(localized: "wipe", defaultValue: "Wipe")
            case .overlay: String(localized: "opacityOverlay", defaultValue: "Opacity Overlay")
            case .heatmap: String(localized: "heatmap", defaultValue: "Heatmap")
        }
    }

    private var canvasSize: CGSize {
        let dimensions = baseImage?.size ?? headImage?.size ?? CGSize(width: 640, height: 480)
        let scale = min(900 / max(dimensions.width, 1), 650 / max(dimensions.height, 1), 1)
        return CGSize(width: dimensions.width * scale, height: dimensions.height * scale)
    }

    private var pixelZoom: Double {
        let size = baseImage?.size ?? headImage?.size ?? .zero
        return min(4, max(0.5, size.width / max(canvasSize.width, 1)))
    }

    private func annotationGesture(
        rect: CGRect,
        target: SnapshotAnnotationTarget,
        image: UIImage?,
    ) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                guard let image,
                      rect.contains(value.startLocation),
                      rect.contains(value.location)
                else { return }
                let x1 = min(value.startLocation.x, value.location.x)
                let y1 = min(value.startLocation.y, value.location.y)
                let x2 = max(value.startLocation.x, value.location.x)
                let y2 = max(value.startLocation.y, value.location.y)
                guard let oid = target == .base ? pair.base?.oid : pair.head?.oid else { return }
                do {
                    let rectangle = try NormalizedRectangle(
                        x: (x1 - rect.minX) / rect.width,
                        y: (y1 - rect.minY) / rect.height,
                        width: (x2 - x1) / rect.width,
                        height: (y2 - y1) / rect.height,
                    )
                    annotationDraft = SnapshotAnnotationDraft(
                        path: pair.file.path,
                        target: target,
                        blobOID: oid,
                        rectangle: rectangle,
                        sourceWidth: Int(image.size.width * image.scale),
                        sourceHeight: Int(image.size.height * image.scale),
                    )
                } catch {
                    assertionFailure(
                        "A drag contained by the image must produce a normalized rectangle: \(error)",
                    )
                }
            }
    }

    private func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }

    private func matchingAnnotations(
        target: SnapshotAnnotationTarget,
    ) -> [SnapshotAnnotationV1] {
        let oid = target == .base ? pair.base?.oid : pair.head?.oid
        return parsedAnnotations.filter {
            $0.path == pair.file.path && $0.target == target && $0.blobOID == oid
        }
    }

    private var parsedAnnotations: [SnapshotAnnotationV1] {
        parsedAnnotationState.annotations
    }

    private var parsedAnnotationState: ParsedSnapshotAnnotations {
        let comments = (model.conversationRead?.value.issueComments ?? []) +
            (model.conversationRead?.value.threads.flatMap(\.comments) ?? [])
        var annotations: [SnapshotAnnotationV1] = []
        var malformedCount = 0
        for comment in comments {
            do {
                if let annotation = try SnapshotAnnotationV1.parseMarker(
                    in: comment.bodyMarkdown,
                ) {
                    annotations.append(annotation)
                }
            } catch {
                malformedCount += 1
            }
        }
        return ParsedSnapshotAnnotations(
            annotations: annotations,
            malformedCount: malformedCount,
        )
    }

    private var outdatedAnnotations: [SnapshotAnnotationV1] {
        parsedAnnotations.filter {
            $0.path == pair.file.path &&
                $0.blobOID != pair.base?.oid &&
                $0.blobOID != pair.head?.oid
        }
    }

    private func matchingImageFindings(
        target: SnapshotAnnotationTarget,
    ) -> [SnapshotImageFinding] {
        guard case let .ready(run) = model.imageAnalysisState,
              run.baseOID == pair.base?.oid,
              run.headOID == pair.head?.oid
        else { return [] }
        return run.analysis.findings.filter { $0.target == target }
    }

    private var selectedProvider: AIProvider {
        PatchlightAIUserDefaults.provider(from: providerCode)
    }

    private var selectedPreset: AnalysisPreset {
        PatchlightAIUserDefaults.preset(from: presetCode)
    }

    private var canRunImageAnalysis: Bool {
        globallyEnabled &&
            model.repositorySettings?.aiEnabled == true &&
            model.repositorySettings?.imageAIEnabled == true &&
            model.configuredProviders.contains(selectedProvider) &&
            (selectedPreset != .advanced || !advancedModelID
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var isImageAnalysisRunning: Bool {
        if case .running = model.imageAnalysisState { true } else { false }
    }

    private func providerTitle(_ provider: AIProvider) -> String {
        switch provider {
            case .openAI: "OpenAI"
            case .anthropic: "Anthropic"
        }
    }
}

private struct ParsedSnapshotAnnotations {
    let annotations: [SnapshotAnnotationV1]
    let malformedCount: Int
}

private struct SnapshotAnnotationDraft: Identifiable {
    let id = UUID()
    let path: String
    let target: SnapshotAnnotationTarget
    let blobOID: GitObjectID
    let rectangle: NormalizedRectangle
    let sourceWidth: Int
    let sourceHeight: Int
}

extension SnapshotAnnotationV1 {
    fileprivate var markerID: String {
        "\(path):\(target.rawValue):\(blobOID.rawValue):\(rectangle.x):\(rectangle.y)"
    }
}

private struct SnapshotAnnotationComposer: View {
    private enum TagChoice: String, CaseIterable, Identifiable {
        case none
        case problem
        case question
        case expectedChange
        case nit

        var id: Self {
            self
        }
    }

    @Environment(\.dismiss) private var dismiss
    let draft: SnapshotAnnotationDraft
    let model: PatchlightAppModel
    @State private var commentBody = ""
    @State private var tag = TagChoice.problem

    var content: some View {
        NavigationStack {
            Form {
                LabeledContent(String(localized: "file", defaultValue: "File"), value: draft.path)
                Picker(
                    String(localized: "annotationTag", defaultValue: "Annotation Tag"),
                    selection: $tag,
                ) {
                    Text(String(localized: "noTag", defaultValue: "No Tag")).tag(TagChoice.none)
                    Text(String(localized: "problem", defaultValue: "Problem"))
                        .tag(TagChoice.problem)
                    Text(String(localized: "question", defaultValue: "Question"))
                        .tag(TagChoice.question)
                    Text(String(localized: "expectedChange", defaultValue: "Expected Change"))
                        .tag(TagChoice.expectedChange)
                    Text(String(localized: "nit", defaultValue: "Nit")).tag(TagChoice.nit)
                }
                TextEditor(text: $commentBody).frame(minHeight: 150)
                Label(
                    String(
                        localized: "snapshotAnnotationIsVisible",
                        defaultValue: "This sends a normal visible GitHub file comment with an interoperable Patchlight region marker.",
                    ),
                    systemImage: "paperplane",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle(String(
                localized: "snapshotAnnotation",
                defaultValue: "Snapshot Annotation",
            ))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .cancel)) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "send", defaultValue: "Send")) {
                        let annotation = SnapshotAnnotationV1(
                            path: draft.path,
                            target: draft.target,
                            blobOID: draft.blobOID,
                            rectangle: draft.rectangle,
                            sourceWidth: draft.sourceWidth,
                            sourceHeight: draft.sourceHeight,
                            tag: annotationTag,
                        )
                        Task {
                            await model.postSnapshotAnnotation(annotation, body: commentBody)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        content
    }

    private var annotationTag: SnapshotAnnotationTag? {
        switch tag {
            case .none: nil
            case .problem: .problem
            case .question: .question
            case .expectedChange: .expectedChange
            case .nit: .nit
        }
    }
}

private struct Checkerboard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Canvas { context, size in
                let tile: CGFloat = 12
                for y in stride(from: 0, to: size.height, by: tile) {
                    for x in stride(from: 0, to: size.width, by: tile) {
                        let isDark = (Int(x / tile) + Int(y / tile)).isMultiple(of: 2)
                        context.fill(
                            Path(CGRect(x: x, y: y, width: tile, height: tile)),
                            with: .color(isDark ? Color.gray.opacity(0.18) : Color.white
                                .opacity(0.5)),
                        )
                    }
                }
            }
            content
        }
    }
}

#if DEBUG
    @_spi(Testing)
    @MainActor
    public enum PatchlightSnapshotWorkspaceSnapshots: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Gallery",
                configurations: [
                    SnapshotConfiguration(device: catalystFrame),
                    SnapshotConfiguration(
                        colorScheme: .dark,
                        layoutDirection: .rightToLeft,
                        device: catalystFrame,
                    ),
                ],
                settle: .immediate,
            ) {
                let pair = PatchlightVisualFixtures.snapshotPair
                PatchlightSnapshotWorkspaceView(
                    files: PatchlightVisualFixtures.workspace.files.filter {
                        $0.path.hasSuffix(".png")
                    },
                    model: PatchlightVisualFixtures.workspaceModel(snapshot: .ready(pair)),
                )
                .patchlightBroadwayRoot()
            }
            comparisonCase(name: "Base", mode: .base)
            comparisonCase(name: "Head", mode: .head)
            comparisonCase(name: "SideBySide", mode: .sideBySide)
            comparisonCase(name: "Wipe", mode: .wipe)
            comparisonCase(name: "OpacityOverlay", mode: .overlay)
            comparisonCase(name: "Heatmap", mode: .heatmap)
            SnapshotCase(
                name: "AnnotationRegion",
                configurations: [SnapshotConfiguration(device: catalystFrame)],
                settle: .immediate,
            ) {
                let pair = PatchlightVisualFixtures.snapshotPair
                SnapshotComparisonView(
                    pair: pair,
                    model: PatchlightVisualFixtures.workspaceModel(snapshot: .ready(pair)),
                    initialMode: .head,
                )
                .patchlightBroadwayRoot()
            }
            SnapshotCase(
                name: "AnnotationComposer",
                configurations: [
                    SnapshotConfiguration(device: .iPadFullContent),
                    SnapshotConfiguration(contrast: .increased, device: .iPadFullContent),
                ],
                settle: .immediate,
            ) {
                SnapshotAnnotationComposer(
                    draft: annotationDraft,
                    model: PatchlightVisualFixtures.workspaceModel(),
                )
                .patchlightBroadwayRoot()
            }
            SnapshotCase(
                name: "DimensionMismatch",
                configurations: [SnapshotConfiguration(device: catalystFrame)],
                settle: .immediate,
            ) {
                let pair = PatchlightVisualFixtures.mismatchedSnapshotPair
                SnapshotComparisonView(
                    pair: pair,
                    model: PatchlightVisualFixtures.workspaceModel(snapshot: .ready(pair)),
                )
                .patchlightBroadwayRoot()
            }
        }

        private static func comparisonCase(
            name: String,
            mode: SnapshotComparisonView.Mode,
        ) -> SnapshotCase {
            SnapshotCase(
                name: name,
                configurations: [SnapshotConfiguration(device: catalystFrame)],
                settle: .immediate,
            ) {
                let pair = PatchlightVisualFixtures.snapshotPair
                SnapshotComparisonView(
                    pair: pair,
                    model: PatchlightVisualFixtures.workspaceModel(snapshot: .ready(pair)),
                    initialMode: mode,
                )
                .patchlightBroadwayRoot()
            }
        }

        private static var catalystFrame: SnapshotConfiguration.Frame {
            .fullContent(name: "Catalyst", width: 1280, minimumHeight: 900)
        }

        private static var annotationDraft: SnapshotAnnotationDraft {
            SnapshotAnnotationDraft(
                path: PatchlightVisualFixtures.snapshotPair.file.path,
                target: .head,
                blobOID: PatchlightVisualFixtures.snapshotHeadOID,
                rectangle: normalizedRectangle,
                sourceWidth: 640,
                sourceHeight: 420,
            )
        }

        private static var normalizedRectangle: NormalizedRectangle {
            do {
                return try NormalizedRectangle(x: 0.58, y: 0.16, width: 0.25, height: 0.22)
            } catch {
                preconditionFailure("The annotation snapshot rectangle must be valid: \(error)")
            }
        }
    }
#endif
