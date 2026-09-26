import BroadwayUI
import DaylightCore
import SnapshotKit
import SwiftUI

struct DeliveryRecoveryView: View {
    @Bindable var model: DaylightModel
    let sequenceID: SolarEvent.ID
    let deliveryID: PublishingDelivery.ID
    @State private var postURL = ""
    @State private var confirmingAbsence = false
    var body: some View {
        Form {
            Section {
                Text(.recoveryPublishingHelp)
                Button(.recoveryPublishingRetry) { Task { await model.recoverDelivery(
                    sequenceID: sequenceID,
                    deliveryID: deliveryID,
                    action: .retry,
                ) } }
                Button(.recoveryPublishingAbsent) { confirmingAbsence = true }
            }.disabled(model.working)
            Section {
                TextField(.recoveryPublishingUrl, text: $postURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Button(.recoveryPublishingRecord) { Task { await model.recordPublishedPost(
                    sequenceID: sequenceID,
                    deliveryID: deliveryID,
                    url: postURL,
                ) } }
                .disabled(model.working || postURL.isEmpty)
            }
            if let notice = model.notice { Section { Text(notice) } }
        }
        .navigationTitle(Text(.recoveryPublishingTitle))
        .confirmationDialog(
            Text(.recoveryPublishingConfirm),
            isPresented: $confirmingAbsence,
            titleVisibility: .visible,
        ) {
            Button(.recoveryPublishingAbsent) { Task { await model.recoverDelivery(
                sequenceID: sequenceID,
                deliveryID: deliveryID,
                action: .confirmedAbsent,
            ) } }
            Button(.recoveryCancel, role: .cancel) {}
        }
    }
}

#if DEBUG
    #Preview {
        let sequence = DaylightPreviewSupport.completedSequence()
        DeliveryRecoveryView(
            model: DaylightPreviewSupport.model(),
            sequenceID: sequence.id,
            deliveryID: sequence.deliveries[0].id,
        )
    }
#endif

#if DEBUG
    extension DeliveryRecoveryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Standard",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack {
                    let sequence = DaylightPreviewSupport.recoverySequence()
                    DeliveryRecoveryView(
                        model: DaylightModel.recoveryPreview(),
                        sequenceID: sequence.id,
                        deliveryID: sequence.deliveries[0].id,
                    )
                }.broadwayRoot()
            }
            SnapshotCase(
                name: "Accessibility",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack {
                    let sequence = DaylightPreviewSupport.recoverySequence()
                    DeliveryRecoveryView(
                        model: DaylightModel.recoveryPreview(),
                        sequenceID: sequence.id,
                        deliveryID: sequence.deliveries[0].id,
                    )
                }.broadwayRoot().dynamicTypeSize(.accessibility3)
            }
        }
    }
#endif
