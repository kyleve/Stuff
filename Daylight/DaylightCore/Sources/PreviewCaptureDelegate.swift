import AVFoundation
import CoreImage
import Foundation
import Synchronization

/// Drops stale preview frames and limits display work to four frames per second.
final class PreviewCaptureDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate,
    Sendable
{
    private let renderer = JPEGRenderer()
    private let lastFrame = Mutex<Date?>(nil)
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    init(continuation: AsyncThrowingStream<Data, any Error>.Continuation) {
        self.continuation = continuation
    }

    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection,
    ) {
        let eligible = lastFrame.withLock { value in
            let now = Date()
            if let value, now.timeIntervalSince(value) < 0.25 { return false }
            value = now
            return true
        }
        guard eligible, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do { try continuation.yield(renderer.renderJPEG(
            CIImage(cvPixelBuffer: buffer),
            maximumDimension: 960,
        )) } catch { continuation.finish(throwing: error) }
    }

    func finish() {
        continuation.finish()
    }
}
