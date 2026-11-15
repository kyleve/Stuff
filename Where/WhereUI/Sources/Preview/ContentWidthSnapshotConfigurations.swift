#if DEBUG
    import SnapshotKit

    /// Full-content captures retain the shared device profiles' insets and traits.
    enum ContentWidthSnapshotConfigurations {
        static var landscapeTablet: SnapshotConfiguration {
            fullContent(.init(device: SnapshotConfiguration.DeviceProfile.iPadPro11
                    .frame(orientation: .landscape)))
        }

        static var wideScreens: [SnapshotConfiguration] {
            [landscapeTablet, fullContent(.init(device: .duoInnerLandscape))]
        }

        private static func fullContent(_ configuration: SnapshotConfiguration)
            -> SnapshotConfiguration
        {
            var configuration = configuration
            guard case let .fixed(size) = configuration.device.size else {
                preconditionFailure("Content-width coverage requires a device viewport")
            }
            configuration.device.name += "-content"
            configuration.device.size = .fullContent(width: size.width, minimumHeight: size.height)
            return configuration
        }
    }
#endif
