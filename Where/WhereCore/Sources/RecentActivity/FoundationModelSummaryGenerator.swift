import Foundation
import FoundationModels

/// On-device `ActivitySummaryGenerating` backed by Apple's Foundation Models.
/// Runs entirely on device (no network, no data leaves the phone), which suits
/// summarizing location history over the selected window. Reports an
/// `ActivitySummaryUnavailableError` when the system model can't run so the UI
/// can guide the user rather than showing a generic failure.
public struct FoundationModelSummaryGenerator: ActivitySummaryGenerating {
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
    /// Times use the current locale/time zone so the summary reads naturally,
    /// and the covered period is described from the interval rather than a fixed
    /// "last 24 hours" so it stays honest across the selectable windows.
    private static func prompt(for input: RecentActivityInput) -> String {
        let readings = input.segments
            .map { segment in
                let coordinate =
                    "\(segment.coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), " +
                    "\(segment.coordinate.longitude.formatted(.number.precision(.fractionLength(4))))"
                return "- \(timeSpan(for: segment)): \(segment.region.localizedName) (\(coordinate))"
            }
            .joined(separator: "\n")
        let period = periodPhrase(for: input.interval)

        return """
        These are the regions the device was in from \(period), oldest first, \
        each with the time span it covers:
        \(readings)

        Summarize where the person was over this period.
        """
    }

    /// A single reading renders as one time; a multi-reading stay renders as a
    /// "start – end" span so the model can convey how long it lasted.
    private static func timeSpan(for segment: RecentActivitySegment) -> String {
        let start = segment.start.formatted(date: .abbreviated, time: .shortened)
        guard segment.end > segment.start else { return start }
        let end = segment.end.formatted(date: .abbreviated, time: .shortened)
        return "\(start) – \(end)"
    }

    /// A compact "<start> to <end>" phrase for the covered interval. Not
    /// user-facing UI copy — it's part of the model prompt — so it stays inline
    /// like the rest of the prompt rather than routing through a catalog.
    private static func periodPhrase(for interval: DateInterval) -> String {
        let start = interval.start.formatted(date: .abbreviated, time: .shortened)
        let end = interval.end.formatted(date: .abbreviated, time: .shortened)
        return "\(start) to \(end)"
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
