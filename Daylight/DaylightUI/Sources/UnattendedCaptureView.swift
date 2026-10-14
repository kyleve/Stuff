import DaylightCore
import SwiftUI

struct UnattendedCaptureView: View {
    @Bindable var model: DaylightModel
    @Environment(\.daylightStylesheet) private var stylesheet
    var body: some View {
        ScrollView {
            VStack(spacing: stylesheet.capture.spacing) {
                Text(.captureArmed).font(.largeTitle)
                if case let .suspended(message) = model
                    .mode { Text(message).accessibilityAddTraits(.updatesFrequently) }
                if let next = model.nextCapture {
                    Text(.captureNext).font(.headline)
                    Text(next, format: .dateTime.month().day().hour().minute())
                        .font(.title2.monospacedDigit())
                }
                if let sequence = model.recentHistory
                    .first { SequenceSummaryView(sequence: sequence) }
                if let issue = model.publishingIssue { Text(issue) }
                if let notice = model.notice { Text(notice) }
                Button(.captureStop) { Task { await model.toggleArmed() } }.buttonStyle(.bordered)
            }.frame(maxWidth: .infinity).padding(stylesheet.capture.padding)
        }
        .scrollEdgeEffectHidden()
        .foregroundStyle(stylesheet.capture.foreground)
        .background(stylesheet.capture.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
    #Preview { UnattendedCaptureView(model: DaylightPreviewSupport.model()) }
#endif
