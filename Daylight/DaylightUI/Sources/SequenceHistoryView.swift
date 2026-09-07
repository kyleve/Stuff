import BroadwayUI
import DaylightCore
import SnapshotKit
import SwiftUI

struct SequenceHistoryView: View {
    let sequences: [CaptureSequence]
    var manualCaptures: [ManualCapture] = []
    var body: some View {
        List {
            if sequences.isEmpty,
               manualCaptures.isEmpty { Text(.historyEmpty).foregroundStyle(.secondary) }
            if !manualCaptures.isEmpty {
                Section(String(localized: .captureTest)) {
                    ForEach(manualCaptures) { capture in
                        VStack(alignment: .leading) {
                            Text(capture.date, format: .dateTime.month().day().hour().minute())
                            switch capture.state {
                                case .capturing: Text(.photosSaving)
                                case let .captured(image): Text(CaptureSequence.Slot.State
                                        .captured(image).title)
                                case let .failed(message): Text(message)
                            }
                        }
                    }
                }
            }
            ForEach(sequences) { sequence in
                Section {
                    SequenceSummaryView(sequence: sequence)
                    ForEach(sequence.slots) { slot in
                        VStack(alignment: .leading) {
                            Text(slot.scheduledAt, format: .dateTime.hour().minute())
                            Text(slot.state.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.navigationTitle(Text(.historyTitle))
    }
}

#if DEBUG
    #Preview { SequenceHistoryView.snapshotPreviews }
#endif

#if DEBUG
    extension SequenceHistoryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "SequenceHistoryView",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack {
                    SequenceHistoryView(sequences: [DaylightPreviewSupport.completedSequence()])
                }
                .broadwayRoot()
            }
        }
    }
#endif
