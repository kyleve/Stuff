import Foundation

public struct ReportActivityState: Equatable, Sendable {
    public let generatedAt: Date
    public let triggerDescription: String

    public init(
        generatedAt: Date,
        triggerDescription: String,
    ) {
        self.generatedAt = generatedAt
        self.triggerDescription = triggerDescription
    }
}
