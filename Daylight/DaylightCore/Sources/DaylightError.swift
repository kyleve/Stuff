import Foundation

public enum DaylightError: Error, LocalizedError, Sendable {
    case invalidSettings, unavailableCamera, cameraPermission, photosPermission, insufficientStorage
    case invalidImage, unsupportedVersion, invalidStore, noScoredImages
    case interrupted, ambiguousPhotosSave, unavailableAsset
    case service(String)

    public var errorDescription: String? {
        switch self {
            case .invalidSettings: "Check the location, schedule, and camera settings."
            case .unavailableCamera: "The selected camera is unavailable."
            case .cameraPermission: "Allow camera access in Settings to capture photos."
            case .photosPermission: "Allow Photos access in Settings to save reversible edits."
            case .insufficientStorage: "Free storage to continue capturing. Pending photos are preserved."
            case .invalidImage: "The image could not be decoded or rendered."
            case .unsupportedVersion: "This data was saved by an unsupported version of Daylight."
            case .invalidStore: "The capture archive is inconsistent. Its files have been preserved."
            case .noScoredImages: "No suitable image could be scored. The sequence is preserved."
            case .interrupted: "Capture was interrupted. Future slots resume when the camera is available."
            case .ambiguousPhotosSave: "A Photos save was interrupted. Check Photos before retrying."
            case .unavailableAsset: "The saved photo is no longer accessible."
            case let .service(message): message
        }
    }
}
