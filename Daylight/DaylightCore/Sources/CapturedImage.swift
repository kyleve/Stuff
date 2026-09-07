import Foundation

public struct CapturedImage: Codable, Equatable, Sendable, Identifiable {
    public var id: CaptureSequence.Slot.ID
    public let capturedAt: Date
    public let recipe: ImageRecipe
    public var photos: PhotosState
    public var score: ScoreState

    public enum PhotosState: Codable, Equatable, Sendable {
        case pending, saving(String), saved(String), failed(String), ambiguous
    }

    public enum ScoreState: Codable, Equatable, Sendable {
        case pending, scored(ImageScore), failed(String)
    }

    public init(id: CaptureSequence.Slot.ID, capturedAt: Date, recipe: ImageRecipe) {
        self.id = id; self.capturedAt = capturedAt; self.recipe = recipe
        photos = .pending; score = .pending
    }
}
