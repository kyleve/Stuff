import AVFoundation
import CoreImage
import Foundation
import Synchronization

/// Drops busy/old frames and limits processed preview work to four frames per second.
final class PreviewCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    Sendable
{
    struct State {
        var recipe: ImageRecipe
        var lastFrame = Date.distantPast
    }

    private let processor = ImageProcessor()
    private let state: Mutex<State>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    init(recipe: ImageRecipe, continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        state = Mutex(State(recipe: recipe)); self.continuation = continuation
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection,
    ) {
        let recipe: ImageRecipe? = state.withLock { value in
            let now = Date()
            guard now.timeIntervalSince(value.lastFrame) >= 0.25 else { return nil }
            value.lastFrame = now
            return value.recipe
        }
        guard let recipe, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            let data = try processor.renderJPEG(
                CIImage(cvPixelBuffer: buffer),
                recipe: recipe,
                maximumDimension: 960,
            )
            continuation.yield(data)
        } catch { continuation.finish(throwing: error) }
    }

    func finish() {
        continuation.finish()
    }
}
