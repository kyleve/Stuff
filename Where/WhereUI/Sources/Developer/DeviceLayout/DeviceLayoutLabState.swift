#if DEBUG
    import Observation

    /// View-owned controls. Changing a layout keeps the demo world; Reset replaces it.
    @MainActor @Observable
    final class DeviceLayoutLabState {
        var configuration: DeviceLayoutConfiguration
        private(set) var model: WhereDemoWorldModel

        struct LoadID: Hashable {
            let model: ObjectIdentifier
            let request: Int
        }

        var loadID: LoadID {
            LoadID(model: ObjectIdentifier(model), request: model.request)
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
