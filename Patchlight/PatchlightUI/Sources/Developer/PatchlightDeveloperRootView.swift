#if DEBUG
    import Foundation
    import Inspector
    import SwiftUI

    /// The standalone DEBUG Inspector runtime selected before app launch.
    public struct PatchlightDeveloperRootView: View {
        private let configuration: InspectorConfiguration
        private let modeController: InspectorModeController

        public init(
            modeController: InspectorModeController,
            fileManager: FileManager = .default,
            userDefaults: UserDefaults = .standard,
            bundleIdentifier: String,
        ) {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
            )[0]
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            configuration = InspectorConfiguration(
                title: "Patchlight Inspector",
                fileContainers: [
                    .init(
                        id: .init(rawValue: "application-support"),
                        title: "Application Support",
                        rootURL: applicationSupport,
                    ),
                    .init(id: .init(rawValue: "caches"), title: "Caches", rootURL: caches),
                    .init(
                        id: .init(rawValue: "temporary"),
                        title: "Temporary",
                        rootURL: fileManager.temporaryDirectory,
                    ),
                ],
                defaultsDomains: [
                    .init(
                        id: .init(rawValue: "standard"),
                        title: "Patchlight",
                        userDefaults: userDefaults,
                        persistentDomainName: bundleIdentifier,
                    ),
                ],
                swiftDataSources: [],
            )
            self.modeController = modeController
        }

        public var body: some View {
            InspectorView(configuration: configuration, modeController: modeController)
        }
    }
#endif
