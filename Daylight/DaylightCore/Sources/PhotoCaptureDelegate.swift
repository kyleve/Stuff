import AVFoundation
import Foundation
import Synchronization

/// Waits for the final capture callback so RAW and JPEG remain one shutter event.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, Sendable {
    private struct State {
        var continuation: CheckedContinuation<CameraCapture, any Error>?
        var jpeg: Data?
        var raw: Data?
    }

    private let state: Mutex<State>
    private let expectsRAW: Bool
    init(expectsRAW: Bool, continuation: CheckedContinuation<CameraCapture, any Error>) {
        self.expectsRAW = expectsRAW; state = Mutex(State(continuation: continuation))
    }

    func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?,
    ) {
        state.withLock { state in
            guard let continuation = state.continuation else { return }
            if let error { state.continuation = nil; continuation.resume(throwing: error); return }
            guard let data = photo.fileDataRepresentation() else {
                state.continuation = nil; continuation
                    .resume(throwing: DaylightError.invalidImage); return
            }
            if photo.isRawPhoto { state.raw = data } else { state.jpeg = data }
        }
    }

    func photoOutput(
        _: AVCapturePhotoOutput,
        didFinishCaptureFor _: AVCaptureResolvedPhotoSettings,
        error: (any Error)?,
    ) {
        state.withLock { state in
            guard let continuation = state.continuation else { return }
            state.continuation = nil
            if let error { continuation.resume(throwing: error); return }
            guard let jpeg = state.jpeg, !expectsRAW || state.raw != nil else {
                continuation.resume(throwing: DaylightError.invalidImage); return
            }
            continuation.resume(returning: CameraCapture(jpeg: jpeg, raw: state.raw))
        }
    }

    func cancel() {
        state
            .withLock { state in
                state.continuation?.resume(throwing: CancellationError()); state.continuation = nil
            }
    }
}
