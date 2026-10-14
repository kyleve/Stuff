import Foundation

public struct CapturedImage: Codable, Equatable, Sendable, Identifiable {
    public var id: CaptureSequence.Slot.ID
    public let capturedAt: Date
    /// Older captures did not record a format or delivery checkpoint.
    public let format: Format?
    public enum Format: String, Codable, Sendable { case jpeg, rawAndJPEG }

    public var photos: PhotosState
    public var score: ScoreState
    public var capturedEventHandled: Bool? = false

    public enum PhotosState: Codable, Equatable, Sendable {
        case pending, saving(String?), saved(String), failed(String), ambiguous
        case retry(Date, String)
        public var needsRecovery: Bool {
            switch self { case .saving, .failed, .ambiguous, .retry: true; case .pending,
                     .saved: false }
        }

        public var requiresAbsenceConfirmation: Bool {
            switch self { case .saving, .ambiguous: true; case .pending, .saved, .failed,
                     .retry: false }
        }
    }

    public enum ScoreState: Codable, Equatable, Sendable {
        case pending, scored(ImageScore), failed(String)
    }

    public init(id: CaptureSequence.Slot.ID, capturedAt: Date, format: Format) {
        self.id = id; self.capturedAt = capturedAt; self.format = format
        photos = .pending; score = .pending
    }
}
