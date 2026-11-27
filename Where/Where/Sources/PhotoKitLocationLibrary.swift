import CoreLocation
import Foundation
import Photos
import RegionKit
import WhereCore

struct PhotoKitLocationLibrary: PhotoLocationReading {
    func access(requestIfNeeded: Bool) async -> PhotoLibraryAccess {
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if requestIfNeeded, status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        switch status {
            case .authorized: return .full
            case .limited: return .limited
            case .notDetermined: return .undetermined
            default: return .unavailable
        }
    }

    @concurrent
    func enumerate(
        in window: DateInterval,
        consume: @Sendable ([PhotoObservation], Int, Int) async throws -> Void,
    ) async throws {
        try Task.checkCancellation()
        let options = PHFetchOptions()
        options.includeAssetSourceTypes = [.typeUserLibrary]
        options.includeHiddenAssets = false
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate <= %@",
            window.start as NSDate,
            window.end as NSDate,
        )
        let result = PHAsset.fetchAssets(with: .image, options: options)
        let size = 128
        for start in stride(from: 0, to: result.count, by: size) {
            try Task.checkCancellation()
            let end = min(start + size, result.count)
            let batch = autoreleasepool {
                (start ..< end).compactMap { index -> PhotoObservation? in
                    let asset = result.object(at: index)
                    return Self.observation(
                        source: asset.sourceType,
                        hidden: asset.isHidden,
                        capturedAt: asset.creationDate,
                        addedAt: asset.addedDate,
                        location: asset.location,
                    )
                }
            }
            try await consume(batch, end, result.count)
        }
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            // A user can remove individual assets while leaving the grant limited.
            let current = PHAsset.fetchAssets(with: .image, options: options)
            for index in 0 ..< result.count {
                try Task.checkCancellation()
                guard current.index(of: result.object(at: index)) != NSNotFound else {
                    throw PhotoScanError.accessChanged
                }
            }
        }
    }

    static func observation(
        source: PHAssetSourceType,
        hidden: Bool,
        capturedAt: Date?,
        addedAt: Date?,
        location: CLLocation?,
    ) -> PhotoObservation? {
        guard source == .typeUserLibrary, !hidden, let location else { return nil }
        let coordinate = location.coordinate
        return PhotoObservation(
            capturedAt: capturedAt,
            addedAt: addedAt,
            coordinate: Coordinate(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
            ),
            accuracy: location.horizontalAccuracy,
        )
    }
}
