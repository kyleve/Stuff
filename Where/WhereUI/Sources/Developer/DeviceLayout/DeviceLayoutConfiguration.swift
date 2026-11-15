#if DEBUG
    import SnapshotKit
    import SwiftUI

    /// The lab's typed selection combines ordinary device orientation with Duo poses.
    enum DeviceLayoutConfiguration: Hashable, Identifiable {
        case device(
            SnapshotConfiguration.DeviceProfile,
            SnapshotConfiguration.DeviceProfile.Orientation,
        )
        case duo(SnapshotConfiguration.DuoPose)

        var id: Self {
            self
        }

        var title: String {
            switch self {
                case let .device(profile, orientation):
                    String(localized: .developerDeviceConfiguration(
                        profile.title,
                        orientation.title,
                    ))
                case let .duo(pose): pose.title
            }
        }

        var frame: SnapshotConfiguration.Frame {
            switch self {
                case let .device(profile, orientation): profile.frame(orientation: orientation)
                case let .duo(pose): pose.frame
            }
        }

        var size: CGSize {
            guard case let .fixed(size) = frame.size else {
                preconditionFailure("Device layouts require bounded viewports")
            }
            return size
        }

        var regions: [AdaptivePaneReservedRegion] {
            switch self {
                case .device: []
                case let .duo(pose): pose.regions
            }
        }
    }
#endif
