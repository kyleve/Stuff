import Foundation
import Photos
import Synchronization

/// Saves original and adjustment output in the same Photos transaction, without per-shot edit
/// prompts.
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
        return PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).count == 1
    }

    public func save(
        originalURL: URL,
        renderedURL: URL,
        recipe: ImageRecipe,
        capturedAt: Date,
        recordIdentifier: @escaping @Sendable (String) async throws
            -> Void,
    ) async throws -> String {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited
        else { throw DaylightError.photosPermission }
        let recipeData = try JSONEncoder().encode(recipe)
        // New asset placeholders only exist inside a change block. Persist their ID synchronously
        // through a local sidecar before the transaction can commit; the owner reconciles it on
        // restart.
        let receiptURL = originalURL.deletingPathExtension()
            .appendingPathExtension("photos-receipt")
        let result = Mutex<Result<String, any Error>?>(nil)
        try await PHPhotoLibrary.shared().performChanges {
            do {
                guard let request = PHAssetChangeRequest
                    .creationRequestForAssetFromImage(atFileURL: originalURL),
                    let placeholder = request.placeholderForCreatedAsset
                else { throw DaylightError.invalidImage }
                request.creationDate = capturedAt
                let output = PHContentEditingOutput(placeholderForCreatedAsset: placeholder)
                output.adjustmentData = PHAdjustmentData(
                    formatIdentifier: "com.stuff.daylight.recipe",
                    formatVersion: "1",
                    data: recipeData,
                )
                try Data(contentsOf: renderedURL).write(
                    to: output.renderedContentURL,
                    options: .atomic,
                )
                try Data(placeholder.localIdentifier.utf8).write(to: receiptURL, options: .atomic)
                request.contentEditingOutput = output
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
