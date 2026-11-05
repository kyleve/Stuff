import SFSafeSymbols
import SwiftUI

/// Shared feedback for reviewed control edits, including refreshed scope and uncertain receipts.
struct RecordingControlStatus: View {
    enum Context {
        case calendar, ignore, place

        var refreshed: String {
            switch self {
                case .calendar: String(localized: .recordingCalendarRefreshed)
                case .ignore, .place: String(localized: .recordingReviewRefreshed)
            }
        }

        var saved: String {
            switch self {
                case .calendar: String(localized: .recordingCalendarSaved)
                case .ignore: String(localized: .recordingIgnoreSaved)
                case .place: String(localized: .recordingPlaceSaved)
            }
        }

        var identifier: String {
            switch self {
                case .calendar: "where_recording_calendar"
                case .ignore: "where_recording_ignore"
                case .place: "where_recording_place"
            }
        }

        @MainActor func failure(_ error: any Error) -> String {
            switch self {
                case .calendar: WhereFormat.recordingCalendarFailure(error)
                case .ignore: WhereFormat.recordingIgnoreFailure(error)
                case .place: WhereFormat.recordingPlaceFailure(error)
            }
        }
    }

    let model: RecordingControlModel
    let context: Context
    let canRetry: Bool
    let retry: () -> Void

    var body: some View {
        switch model.state {
            case .idle, .retired: EmptyView()
            case .reviewing:
                Section { ProgressView(String(localized: .recordingReviewLoading)) }
            case let .ready(review) where review.refreshed:
                Section {
                    Label(context.refreshed, systemSymbol: .arrowClockwise)
                        .accessibilityIdentifier(context.identifier + "_refreshed")
                }
            case .ready: EmptyView()
            case .saving:
                Section { SavingStatusRow(text: String(localized: .manualSavingStatus)) }
            case .applied:
                Section {
                    Label(context.saved, systemSymbol: .checkmarkCircle)
                        .accessibilityIdentifier(context.identifier + "_saved")
                }
            case let .failed(error, _):
                Section {
                    Label(context.failure(error), systemSymbol: .exclamationmarkTriangle)
                    if canRetry {
                        Button(String(localized: .commonRetry), action: retry)
                            .accessibilityIdentifier(context.identifier + "_retry")
                    }
                }
        }
    }
}

#if DEBUG
    #Preview { RecordingCalendarEditor.snapshotPreviews }
#endif
