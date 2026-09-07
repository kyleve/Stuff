import DaylightCore
import Foundation

actor PreviewTestCamera: CameraCapturing {
    let allowed: Bool
    let frame: Data
    private(set) var accessRequests = 0
    private(set) var previewStarts = 0

    init(allowed: Bool, frame: Data) {
        self.allowed = allowed; self.frame = frame
    }

    func requestAccess() -> Bool {
        accessRequests += 1
        return allowed
    }

    func availableLenses() -> [CaptureSettings.Camera.Lens] {
        [.main]
    }

    func capture(settings _: CaptureSettings.Camera) throws -> CameraCapture {
        throw DaylightError.unavailableCamera
    }

    func preview(settings _: CaptureSettings.Camera) -> AsyncThrowingStream<Data, any Error> {
        previewStarts += 1
        return AsyncThrowingStream { continuation in
            continuation.yield(frame)
            continuation.finish()
        }
    }

    func stop() {}
}
