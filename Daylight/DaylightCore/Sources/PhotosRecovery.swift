import Foundation

/// Determines safe recovery from durable receipts without creating another Photos asset.
enum PhotosRecovery {
    static func identifier(originalURL: URL, recorded: String?) throws -> String? {
        if let recorded { return recorded }
        let receipt = originalURL.deletingPathExtension().appendingPathExtension("photos-receipt")
        guard FileManager.default.fileExists(atPath: receipt.path) else { return nil }
        return try String(contentsOf: receipt, encoding: .utf8)
    }

    static func failure(
        _ error: any Error,
        originalURL: URL,
        recorded: String?,
        now: Date,
    ) throws -> CapturedImage.PhotosState {
        if let failure = error as? PhotosSaveFailure {
            return .retry(now.addingTimeInterval(30), failure.localizedDescription)
        }
        if let identifier = try identifier(originalURL: originalURL, recorded: recorded) {
            return .saving(identifier)
        }
        return .ambiguous
    }
}
