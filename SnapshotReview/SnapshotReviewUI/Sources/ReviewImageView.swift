import SnapshotReviewCore
import SwiftUI

struct ReviewImageView: View {
    let image: SnapshotImage
    let loader: any ReviewImageLoading
    let thumbnail: Bool
    let model: ReviewBrowserModel
    @Environment(\.reviewStyle) private var style
    private struct LoadedBitmap {
        let bitmap: CGImage
        let request: Request
    }

    private struct Request: Hashable {
        let imageID: SnapshotImage.ID
        let fingerprint: String?
    }

    @State private var result: Result<LoadedBitmap, any Error>?
    @State private var command = ReviewCanvas.CanvasCommand()

    var body: some View {
        VStack {
            if !thumbnail {
                HStack {
                    Button("Fit") { issue(.fit) }
                    Button("Actual Pixels") { issue(.actual) }
                    Button("Zoom Out") { issue(.zoomOut) }
                    Button("Zoom In") { issue(.zoomIn) }
                    Spacer()
                    if model
                        .placement !=
                        nil
                    {
                        Text("Click the image to place the point").foregroundStyle(.secondary)
                    }
                }
            }
            switch result {
                case let .success(loaded):
                    if thumbnail {
                        Image(decorative: loaded.bitmap, scale: 1).resizable().scaledToFit()
                    } else if case let .success(content) = image.content {
                        ReviewCanvas(
                            image: loaded.bitmap,
                            annotations: loaded.request == request ? model.review(image)?
                                .annotations ?? [] : [],
                            fingerprint: content.fingerprint,
                            selected: model.selectedAnnotation,
                            isPlacing: model.placement != nil && loaded.request == request,
                            command: command,
                            style: style.canvas,
                            onPoint: { point in Task { await model.place(point) } },
                            onSelect: { model.selectedAnnotation = $0 },
                        )
                    }
                case let .failure(error):
                    ContentUnavailableView { Text("Image unavailable") } description: {
                        Text(error.localizedDescription)
                    }
                case nil: ProgressView()
            }
        }
        .background(.background)
        .overlay {
            if case let .success(loaded) = result, loaded.request != request {
                ProgressView("Loading selected image…").padding().background(.regularMaterial)
            }
        }
        .task(id: request) { await load() }
        .onDisappear {
            if !thumbnail, model.displayedImage?.imageID == image.id { model.displayedImage = nil }
        }
    }

    private var request: Request {
        .init(imageID: image.id, fingerprint: contentFingerprint)
    }

    private var contentFingerprint: String? {
        if case let .success(content) = image.content { content.fingerprint } else { nil }
    }

    private func load() async {
        if !thumbnail { model.displayedImage = nil }
        do {
            let bitmap = try await loader.image(image, thumbnail: thumbnail)
            try Task.checkCancellation()
            result = .success(LoadedBitmap(bitmap: bitmap, request: request))
            if !thumbnail, model.selectedImage?.id == image.id,
               let fingerprint = contentFingerprint
            {
                model.displayedImage = .init(imageID: image.id, fingerprint: fingerprint)
            }
        } catch is CancellationError {
            return
        } catch { result = .failure(error) }
    }

    private func issue(_ action: ReviewCanvas.CanvasCommand.Action) {
        command.action = action; command.revision += 1
    }
}

#if DEBUG
    import BroadwayUI
    import SnapshotKit

    extension ReviewImageView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let loader = ReviewPreviewImageLoader(bitmap: ReviewPreviewFixtures.bitmap())
            return [SnapshotCase(
                name: "PinnedImage",
                configurations: [.init(device: .iPadFullContent2D)],
                onReadyToMeasure: { await loader.waitForLoads(1) },
                settle: .settledAtLeast(minDuration: 0.3),
                onReadyToSnapshot: { await loader.waitForLoads(1) },
            ) {
                let model = ReviewPreviewFixtures.model(loaded: true, single: true)
                if let image = model.selectedImage {
                    ReviewImageView(image: image, loader: loader, thumbnail: false, model: model)
                        .broadwayRoot()
                }
            }]
        }
    }

    #Preview { ReviewImageView.snapshotPreviews }
#endif
