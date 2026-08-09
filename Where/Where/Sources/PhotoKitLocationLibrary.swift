import Foundation
import Photos
import RegionKit
import WhereCore

/// Production, metadata-only Photos adapter for onboarding history import.
/// It never asks PhotoKit for image data or thumbnails and never performs a
/// photo-library change request.
struct PhotoKitLocationLibrary: PhotoLocationLibrary {
    func authorizationStatus() async -> PhotoLibraryAuthorization {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestAuthorization() async -> PhotoLibraryAuthorization {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: Self.map(status))
            }
        }
    }

    @concurrent
    func assets(in interval: DateInterval) async throws -> [PhotoLocationAsset] {
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue,
            interval.start as NSDate,
            interval.end as NSDate,
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        let fetched = PHAsset.fetchAssets(with: options)
        var values: [PhotoLocationAsset] = []
        values.reserveCapacity(fetched.count)
        for index in 0 ..< fetched.count {
            try Task.checkCancellation()
            let asset = fetched.object(at: index)
            values.append(PhotoLocationAsset(
                capturedAt: asset.creationDate,
                addedAt: asset.addedDate,
                coordinate: asset.location.map {
                    Coordinate(
                        latitude: $0.coordinate.latitude,
                        longitude: $0.coordinate.longitude,
                    )
                },
                horizontalAccuracy: asset.location?.horizontalAccuracy,
                source: Self.map(asset.sourceType),
                isHidden: asset.isHidden,
            ))
        }
        return values
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoLibraryAuthorization {
        switch status {
            case .notDetermined: .notDetermined
            case .restricted: .restricted
            case .denied: .denied
            case .authorized: .authorized
            case .limited: .limited
            @unknown default: .denied
        }
    }

    private static func map(_ source: PHAssetSourceType) -> PhotoAssetLibrarySource {
        if source.contains(.typeCloudShared) { return .cloudShared }
        if source.contains(.typeiTunesSynced) { return .synced }
        return .userLibrary
    }
}
