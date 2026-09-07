import Foundation
import Vision

public struct VisionImageScorer: ImageScoring {
    public init() {}
    public func score(_ image: Data) async throws -> ImageScore {
        let observation = try await CalculateImageAestheticsScoresRequest().perform(on: image)
        return ImageScore(overall: observation.overallScore, isUtility: observation.isUtility)
    }
}
