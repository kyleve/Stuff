import AppIntents
import Foundation
import WhereCore

/// "Summarize where I've been this week." — the on-device Foundation Models
/// narrative of a look-back window. When the model is unavailable the intent
/// speaks the actionable reason (e.g. turn on Apple Intelligence) rather than a
/// generic failure, and logs it.
public struct RecentActivitySummaryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Summarize Recent Activity"

    public static let description = IntentDescription(
        "Get an on-device summary of where you've been over a recent window.",
    )

    @Parameter(title: "Time Range")
    public var window: ActivityWindowAppEnum

    public init() {}

    public init(window: ActivityWindowAppEnum) {
        self.window = window
    }

    private static let logger = WhereLog.channel(.whereIntents)

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let services = try WhereServices.forIntents()
        let reader = WhereIntentReader(services: services)
        do {
            let summary = try await reader.recentActivity(window.window)
            return .result(
                dialog: IntentDialog(
                    "\(IntentStrings.recentActivity(summary, window: window.window))",
                ),
            )
        } catch let error as ActivitySummaryUnavailableError {
            // User-recoverable (Apple Intelligence off, model warming): surface
            // the reason in the dialog and log it — never a silent empty result.
            Self.logger.warning(
                "Recent-activity summary unavailable: \(String(describing: error.reason))",
            )
            return .result(
                dialog: IntentDialog("\(IntentStrings.recentActivityUnavailable(error.reason))"),
            )
        }
    }
}
