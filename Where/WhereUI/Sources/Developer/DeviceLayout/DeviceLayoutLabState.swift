#if DEBUG
    import BroadwayCore
    import Observation

    /// View-owned controls. Changing a layout keeps the demo world; Reset replaces it.
    @MainActor @Observable
    final class DeviceLayoutLabState {
        var configuration: DeviceLayoutConfiguration
        private(set) var model: WhereDemoWorldModel

        struct LoadID: Hashable {
            let model: ObjectIdentifier
            let retryTrigger: EventTrigger
        }

        var loadID: LoadID {
            LoadID(model: ObjectIdentifier(model), retryTrigger: model.retryTrigger)
        }

        init(
            model: WhereDemoWorldModel = WhereDemoWorldModel(),
            configuration: DeviceLayoutConfiguration = .device(.iPhone17, .portrait),
        ) {
            self.model = model
            self.configuration = configuration
        }

        func reset() {
            model = WhereDemoWorldModel()
        }
    }
#endif
