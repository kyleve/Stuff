import Foundation
import FoundationModels
import LogKit

/// On-device `ActivitySummaryGenerating` backed by Apple's Foundation Models.
/// Runs entirely on device (no network, no data leaves the phone), which suits
/// summarizing location history. Reports an `ActivitySummaryUnavailableError`
/// when the system model can't run so the UI can guide the user rather than
/// showing a generic failure.
public struct FoundationModelSummaryGenerator: ActivitySummaryGenerating {
    private static let logger = WhereLog.channel(.recentActivitySummarizer)

    public init() {}

    public func summarize(_ input: RecentActivityInput) async throws -> String {
        switch SystemLanguageModel.default.availability {
            case .available:
                break
            case let .unavailable(reason):
                throw ActivitySummaryUnavailableError(reason: Self.map(reason))
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(to: Self.prompt(for: input))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let instructions = """
    You summarize a person's recent location history for a residency/day-count \
    audit log. You are given timestamped GPS readings and the tracked region \
    each reading falls in. Write a concise, factual, 2-3 sentence summary of \
    where the person appears to have been over the period. Mention the main \
    regions and the rough times or transitions between them. Do not invent \
    places or motives, do not give advice, and do not add a preamble — return \
    only the summary.
    """

    /// Render the structured window into a compact prompt the model can read.
    /// Times use the current locale/time zone so the summary reads naturally.
    private static func prompt(for input: RecentActivityInput) -> String {
        let readings = input.stops
            .map { stop in
                let time = stop.timestamp.formatted(date: .abbreviated, time: .shortened)
                let coordinate =
                    "\(stop.coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), " +
                    "\(stop.coordinate.longitude.formatted(.number.precision(.fractionLength(4))))"
                return "- \(time): \(stop.region.localizedName) (\(coordinate))"
            }
            .joined(separator: "\n")

        return """
        These are the device's location readings over the last 24 hours, oldest first:
        \(readings)

        Summarize where the person was over this period.
        """
    }

    private static func map(
        _ reason: SystemLanguageModel.Availability.UnavailableReason,
    ) -> ActivitySummaryUnavailableReason {
        switch reason {
            case .deviceNotEligible: .deviceNotEligible
            case .appleIntelligenceNotEnabled: .appleIntelligenceNotEnabled
            case .modelNotReady: .modelNotReady
            @unknown default: .unknown
        }
    }
}
