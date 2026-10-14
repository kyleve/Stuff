import BroadwayUI
import DaylightCore
import SnapshotKit
import SwiftUI

struct SequenceHistoryView: View {
    @Bindable var model: DaylightModel
    private var sequences: [CaptureSequence] {
        model.recentHistory
    }

    private var manualCaptures: [ManualCapture] {
        model.manualHistory
    }

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
                                case let .captured(image):
                                    Text(CaptureSequence.Slot.State.captured(image).title)
                                    if image.photos.needsRecovery {
                                        NavigationLink { PhotosRecoveryView(
                                            model: model,
                                            image: image,
                                        ) } label: { Text(.recoveryPhotosTitle) }
                                    }
                                case let .failed(message): Text(message)
                            }
                        }
                    }
                }
            }
            ForEach(sequences) { sequence in
                Section {
                    SequenceSummaryView(sequence: sequence)
                    ForEach(sequence.deliveries.filter(\.state.needsRecovery)) { delivery in
                        NavigationLink { DeliveryRecoveryView(
                            model: model,
                            sequenceID: sequence.id,
                            deliveryID: delivery.id,
                        ) } label: { Text(.recoveryPublishingTitle) }
                    }
                    ForEach(sequence.slots) { slot in
                        VStack(alignment: .leading) {
                            Text(slot.scheduledAt, format: .dateTime.hour().minute())
                            Text(slot.state.title).font(.caption).foregroundStyle(.secondary)
                            if case let .captured(image) = slot.state, image.photos.needsRecovery {
                                NavigationLink { PhotosRecoveryView(model: model, image: image)
                                } label: { Text(.recoveryPhotosTitle) }
                            }
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
                name: "Recovery",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack { SequenceHistoryView(model: DaylightModel.recoveryPreview()) }
                    .broadwayRoot()
            }
            SnapshotCase(
                name: "SequenceHistoryView",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack {
                    SequenceHistoryView(model: DaylightModel.historyPreview())
                }
                .broadwayRoot()
            }
        }
    }
#endif
