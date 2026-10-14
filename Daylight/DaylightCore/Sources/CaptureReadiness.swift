import AVFoundation
import Foundation
import Photos

/// Checks system conditions without requesting permissions or opening the camera.
public protocol CaptureReadiness: Sendable {
    func check() throws
}

public struct SystemCaptureReadiness: CaptureReadiness {
    public init() {}
    public func check() throws {
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal != .serious, thermal != .critical else { throw DaylightError.cooling }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        else { throw DaylightError.cameraPermission }
        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized || authorization == .limited
        else { throw DaylightError.photosPermission }
    }
}
