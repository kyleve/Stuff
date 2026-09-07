import AVFoundation
import Foundation
import Synchronization

/// AVFoundation owns callback threads. The mutex resumes the continuation at most once.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private let continuation: Mutex<CheckedContinuation<Data, any Error>?>
    init(continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = Mutex(continuation)
    }

    func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?,
    ) {
        continuation.withLock { continuation in
            guard let pending = continuation else { return }
            continuation = nil
            if let error { pending.resume(throwing: error) }
            else if let data = photo.fileDataRepresentation() { pending.resume(returning: data) }
            else { pending.resume(throwing: DaylightError.invalidImage) }
        }
    }

    func cancel() {
        continuation.withLock { value in value?.resume(throwing: CancellationError()); value = nil }
    }
}
