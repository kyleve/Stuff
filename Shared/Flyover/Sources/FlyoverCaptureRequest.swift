#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// One fully resolved image request in a web export plan.
    @MainActor
    public struct FlyoverCaptureRequest {
        public let groupTitle: String
        public let screenID: String
        public let screenTitle: String
        public let variantID: String
        public let variantTitle: String
        public let profile: FlyoverCaptureProfile
        public let configuration: SnapshotConfiguration
        public let captureExtent: FlyoverCaptureExtent
        public let measurementReadiness: SnapshotMeasurementReadiness
        public let settle: SnapshotSettle
        public let onReadyToMeasure: (@MainActor () async -> Void)?
        public let onReadyToSnapshot: (@MainActor () async -> Void)?
        public let captureName: String
        public let content: AnyView

        init(
            groupTitle: String,
            screenID: String,
            screenTitle: String,
            variantID: String,
            variantTitle: String,
            profile: FlyoverCaptureProfile,
            configuration: SnapshotConfiguration,
            policy: FlyoverExportPolicy,
            captureName: String,
            content: AnyView,
        ) {
            self.groupTitle = groupTitle
            self.screenID = screenID
            self.screenTitle = screenTitle
            self.variantID = variantID
            self.variantTitle = variantTitle
            self.profile = profile
            self.configuration = configuration
            captureExtent = policy.captureExtent
            measurementReadiness = policy.measurementReadiness
            settle = policy.settle
            onReadyToMeasure = policy.onReadyToMeasure
            onReadyToSnapshot = policy.onReadyToSnapshot
            self.captureName = captureName
            self.content = content
        }
    }
#endif
