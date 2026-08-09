import Foundation
import RegionKit

/// The user's current Photos read authorization, expressed without leaking
/// PhotoKit types into the domain and presentation layers.
public enum PhotoLibraryAuthorization: Sendable, Equatable {
    case notDetermined
    case limited
    case authorized
    case denied
    case restricted
}

/// The broad library bucket PhotoKit reports for an asset. PhotoKit does not
/// expose the identity of the device that originally captured an image.
public enum PhotoAssetLibrarySource: Sendable, Equatable {
    case userLibrary
    case cloudShared
    case synced
}

/// Location-related metadata for one image in the user's Photos library.
///
/// Optional fields preserve malformed/incomplete assets until the pure planner
/// decides whether they are importable. No image data, filename, caption, or
/// Photos identifier crosses this boundary.
public struct PhotoLocationAsset: Sendable, Equatable {
    public let capturedAt: Date?
    public let addedAt: Date?
    public let coordinate: Coordinate?
    public let horizontalAccuracy: Double?
    public let source: PhotoAssetLibrarySource
    public let isHidden: Bool

    public init(
        capturedAt: Date?,
        addedAt: Date?,
        coordinate: Coordinate?,
        horizontalAccuracy: Double?,
        source: PhotoAssetLibrarySource,
        isHidden: Bool,
    ) {
        self.capturedAt = capturedAt
        self.addedAt = addedAt
        self.coordinate = coordinate
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
        self.isHidden = isHidden
    }
}

/// Read-only access to photo location metadata. Production is backed by
/// PhotoKit; tests and previews inject a scripted implementation.
public protocol PhotoLocationLibrary: Sendable {
    func authorizationStatus() async -> PhotoLibraryAuthorization
    func requestAuthorization() async -> PhotoLibraryAuthorization
    func assets(in interval: DateInterval) async throws -> [PhotoLocationAsset]
}

/// Preview/test default that never prompts or returns Photos data.
public struct UnavailablePhotoLocationLibrary: PhotoLocationLibrary {
    public init() {}

    public func authorizationStatus() async -> PhotoLibraryAuthorization {
        .denied
    }

    public func requestAuthorization() async -> PhotoLibraryAuthorization {
        .denied
    }

    public func assets(in _: DateInterval) async throws -> [PhotoLocationAsset] {
        []
    }
}
