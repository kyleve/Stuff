#if DEBUG
    import PeriscopeCore
    @_spi(Testing) import WhereCore

    /// Supplies known devices through setup's production discovery seam without disk or CloudKit.
    @MainActor
    struct OnboardingPreviewBootstrap: WhereScopeAssembling {
        let contextStore: any InstallationRecordingContextStoring
        let devices: [RecordingDevice]

        func prepareLocation() {}

        func discoverRecordingDevices() async throws -> [RecordingDevice] {
            devices
        }

        func makeServices() async throws -> WhereServices {
            try PreviewSupport.onboardingServices(installationContext: contextStore.resolve())
        }

        func makeLogStore() async throws -> PeriscopeStore? {
            nil
        }
    }
#endif
