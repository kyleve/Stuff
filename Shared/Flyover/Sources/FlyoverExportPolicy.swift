#if DEBUG
    import SnapshotKit

    /// The sizing and readiness behavior for one exported Flyover variant.
    @MainActor
    public struct FlyoverExportPolicy {
        public let captureExtent: FlyoverCaptureExtent
        public let measurementReadiness: SnapshotMeasurementReadiness
        public let settle: SnapshotSettle
        public let onReadyToMeasure: (@MainActor () async -> Void)?
        public let onReadyToSnapshot: (@MainActor () async -> Void)?

        public init(
            captureExtent: FlyoverCaptureExtent,
            measurementReadiness: SnapshotMeasurementReadiness,
            settle: SnapshotSettle,
            onReadyToMeasure: (@MainActor () async -> Void)?,
            onReadyToSnapshot: (@MainActor () async -> Void)?,
        ) {
            self.captureExtent = captureExtent
            self.measurementReadiness = measurementReadiness
            self.settle = settle
            self.onReadyToMeasure = onReadyToMeasure
            self.onReadyToSnapshot = onReadyToSnapshot
        }

        public static var hosted: Self {
            FlyoverExportPolicy(
                captureExtent: .viewport,
                measurementReadiness: .sameAsCapture,
                settle: .settled,
                onReadyToMeasure: nil,
                onReadyToSnapshot: nil,
            )
        }

        static func resolution(for snapshotCase: SnapshotCase) -> FlyoverExportPolicyResolution {
            let extents = Set(snapshotCase.configurations.map { configuration in
                switch configuration.device.size {
                    case .fixed: FlyoverCaptureExtent.viewport
                    case .intrinsic: FlyoverCaptureExtent.intrinsic
                    case .fullContent: FlyoverCaptureExtent.fullContent
                    case .fullContent2D: FlyoverCaptureExtent.fullContent2D
                }
            })
            guard extents.count <= 1 else {
                return .mixed(extents.sorted { $0.rawValue < $1.rawValue })
            }
            return .policy(FlyoverExportPolicy(
                captureExtent: extents.first ?? .viewport,
                measurementReadiness: snapshotCase.measurementReadiness,
                settle: snapshotCase.settle,
                onReadyToMeasure: snapshotCase.onReadyToMeasure,
                onReadyToSnapshot: snapshotCase.onReadyToSnapshot,
            ))
        }
    }

    enum FlyoverExportPolicyResolution {
        case policy(FlyoverExportPolicy)
        case mixed([FlyoverCaptureExtent])
    }
#endif
