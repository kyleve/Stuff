import Foundation
import Photos
import Synchronization

/// Saves original RAW and JPEG resources in one Photos asset and records a durable asset identifier
/// for recovery.
public struct PhotosLibrary: PhotosSaving {
    public init() {}
    public func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    public func contains(assetIdentifier: String) async throws -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited
        else { throw DaylightError.photosPermission }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil)
            .firstObject else { return false }
        return asset.mediaType == .image
    }

    public func save(
        originalURL: URL,
        rawURL: URL?,
        capturedAt: Date,
        recordIdentifier: @escaping @Sendable (String) async throws
            -> Void,
    ) async throws -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited
        else { throw DaylightError.photosPermission }
        // New asset placeholders only exist inside a change block. Persist their ID synchronously
        // through a local sidecar before the transaction can commit; the owner reconciles it on
        // restart.
        let receiptURL = originalURL.deletingPathExtension()
            .appendingPathExtension("photos-receipt")
        let result = Mutex<Result<String, any Error>?>(nil)
        try await PHPhotoLibrary.shared().performChanges {
            do {
                let request = PHAssetCreationRequest.forAsset()
                if let rawURL {
                    request.addResource(with: .photo, fileURL: rawURL, options: nil)
                    request.addResource(with: .alternatePhoto, fileURL: originalURL, options: nil)
                } else { request.addResource(with: .photo, fileURL: originalURL, options: nil) }
                guard let placeholder = request.placeholderForCreatedAsset
                else { throw DaylightError.invalidImage }
                request.creationDate = capturedAt
                try Data(placeholder.localIdentifier.utf8).write(to: receiptURL, options: .atomic)
                result.withLock { $0 = .success(placeholder.localIdentifier) }
            } catch {
                result.withLock { $0 = .failure(error) }
            }
        }
        guard let outcome = result.withLock({ $0 }) else { throw DaylightError.invalidStore }
        let identifier = try outcome.get()
        try await recordIdentifier(identifier)
        return identifier
    }
}
