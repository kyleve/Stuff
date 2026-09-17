import BroadwayUI
import DaylightCore
import SnapshotKit
import SwiftUI

struct PhotosRecoveryView: View {
    @Bindable var model: DaylightModel
    let image: CapturedImage
    @State private var confirmingAbsence = false
    var body: some View {
        Form {
            Text(image.capturedAt, format: .dateTime.month().day().hour().minute())
            Text(.recoveryPhotosHelp)
            Button(.recoveryPhotosRetry) { Task { await model.resolvePhotos(
                imageID: image.id,
                resolution: .retry,
            ) } }
            .disabled(model.working)
            if image.photos.requiresAbsenceConfirmation {
                Button(.recoveryPhotosAbsent) { confirmingAbsence = true }.disabled(model.working)
            }
            if let notice = model.notice { Text(notice) }
        }
        .navigationTitle(Text(.recoveryPhotosTitle))
        .confirmationDialog(
            Text(.recoveryPhotosConfirm),
            isPresented: $confirmingAbsence,
            titleVisibility: .visible,
        ) {
            Button(.recoveryPhotosAbsent) { Task { await model.resolvePhotos(
                imageID: image.id,
                resolution: .confirmedAbsent,
            ) } }
            Button(.recoveryCancel, role: .cancel) {}
        }
    }
}

#if DEBUG
    #Preview { PhotosRecoveryView(
        model: DaylightPreviewSupport.model(),
        image: DaylightPreviewSupport.sequence().images[0],
    ) }
#endif

#if DEBUG
    extension PhotosRecoveryView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            SnapshotCase(
                name: "Standard",
                configurations: SnapshotConfiguration.combinations(devices: [.iPhoneFullContent]),
                settle: .immediate,
            ) {
                NavigationStack {
                    let sequence = DaylightPreviewSupport.recoverySequence()
                    PhotosRecoveryView(
                        model: DaylightModel.recoveryPreview(),
                        image: sequence.images[0],
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
                    PhotosRecoveryView(
                        model: DaylightModel.recoveryPreview(),
                        image: sequence.images[0],
                    )
                }.broadwayRoot().dynamicTypeSize(.accessibility3)
            }
        }
    }
#endif
