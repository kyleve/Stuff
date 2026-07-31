#if DEBUG
    import Foundation
    import Inspector
    import PeriscopeCore
    import SwiftUI
    import UIKit
    import WhereCore

    /// The standalone Inspector process. It owns no regular Where launch object;
    /// the only Where-specific work is the injected schema/container factory
    /// needed to inspect the app's persisted records.
    @MainActor
    final class WhereInspectorApplicationRuntime: WhereApplicationRuntime {
        let configuration: InspectorConfiguration
        private let modeController: InspectorModeController

        init(
            modeController: InspectorModeController,
            fileManager: FileManager = .default,
            userDefaults: UserDefaults = .standard,
            bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        ) {
            guard let bundleIdentifier else {
                preconditionFailure("Where has no bundle identifier")
            }
            guard let groupURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: SwiftDataStore.appGroupIdentifier,
            ) else {
                preconditionFailure("Where's App Group container is unavailable")
            }
            let whereStoreURL = SwiftDataStore.inspectorStoreURL(groupContainerURL: groupURL)

            configuration = Self.makeConfiguration(
                fileManager: fileManager,
                userDefaults: userDefaults,
                bundleIdentifier: bundleIdentifier,
                groupURL: groupURL,
                whereStoreURL: whereStoreURL,
                periscopeStoreURL: PeriscopeStore.inspectorStoreURL,
                periscopeRecoveryStorageURLs: PeriscopeStore.inspectorRecoveryStorageURLs,
            )
            self.modeController = modeController
        }

        static func makeConfiguration(
            fileManager: FileManager,
            userDefaults: UserDefaults,
            bundleIdentifier: String,
            groupURL: URL,
            whereStoreURL: URL,
            periscopeStoreURL: URL,
            periscopeRecoveryStorageURLs: [URL],
        ) -> InspectorConfiguration {
            let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let applicationSupport =
                fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]

            return InspectorConfiguration(
                title: "Inspector",
                fileContainers: [
                    .init(id: .init(rawValue: "documents"), title: "Documents", rootURL: documents),
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
                    .init(id: .init(rawValue: "app-group"), title: "App Group", rootURL: groupURL),
                ],
                defaultsDomains: [
                    .init(
                        id: .init(rawValue: "standard"),
                        title: "Where",
                        userDefaults: userDefaults,
                        persistentDomainName: bundleIdentifier,
                    ),
                ],
                swiftDataSources: [
                    .init(
                        id: .init(rawValue: "where"),
                        title: "Where SwiftData",
                        storageRootURL: groupURL,
                        storeURL: whereStoreURL,
                        modelTypes: SwiftDataStore.inspectorModelTypes,
                        makeContainer: {
                            try SwiftDataStore.makeContainer(storage: .localOnly)
                        },
                    ),
                    .init(
                        id: .init(rawValue: "periscope"),
                        title: "Periscope SwiftData",
                        storageRootURL: applicationSupport,
                        storeURL: periscopeStoreURL,
                        recoveryStorageURLs: periscopeRecoveryStorageURLs,
                        modelTypes: PeriscopeStore.inspectorModelTypes,
                        makeContainer: {
                            try PeriscopeStore.makeContainer(storage: .onDisk)
                        },
                    ),
                ],
            )
        }

        func didFinishLaunching(
            application _: UIApplication,
            options _: [UIApplication.LaunchOptionsKey: Any]?,
        ) -> Bool {
            true
        }

        func makeRootView() -> AnyView {
            AnyView(InspectorView(
                configuration: configuration,
                modeController: modeController,
            ))
        }
    }
#endif
