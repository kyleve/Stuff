#if DEBUG
    import Foundation
    import Inspector
    import Observation
    import WhereCore

    /// Owns Where's mutually exclusive DEBUG next-launch choices.
    @MainActor
    @Observable
    public final class WhereDeveloperLaunchController {
        public enum NextLaunch: Equatable, Sendable {
            case regularApplication
            case inspector
            case demo(DemoDataBuilder.Configuration)
        }

        public private(set) var nextLaunch: NextLaunch
        public let inspectorModeController: InspectorModeController

        private let userDefaults: UserDefaults
        private static let demoEnabledKey = "demo.nextLaunch.enabled"
        private static let demoIssueKeyPrefix = "demo.nextLaunch.issue."

        public init(
            userDefaults: UserDefaults,
            inspectorModeController: InspectorModeController,
        ) {
            self.userDefaults = userDefaults
            self.inspectorModeController = inspectorModeController

            if inspectorModeController.nextLaunch == .inspector {
                Self.clearDemo(in: userDefaults)
                nextLaunch = .inspector
            } else if userDefaults.bool(forKey: Self.demoEnabledKey) {
                nextLaunch = .demo(Self.demoConfiguration(in: userDefaults))
            } else {
                nextLaunch = .regularApplication
            }
        }

        /// Build the persistent controller for one Where application.
        public convenience init(applicationIdentifier: String) {
            let suiteName = "\(applicationIdentifier).where-developer-launch-control"
            guard let userDefaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open Where developer launch defaults suite")
            }
            self.init(
                userDefaults: userDefaults,
                inspectorModeController: InspectorModeController(
                    applicationIdentifier: applicationIdentifier,
                ),
            )
        }

        public func scheduleInspector() {
            Self.clearDemo(in: userDefaults)
            inspectorModeController.enterInspectorOnNextLaunch()
            nextLaunch = .inspector
        }

        public func scheduleDemo(_ configuration: DemoDataBuilder.Configuration) {
            inspectorModeController.useRegularApplicationOnNextLaunch()
            persistDemo(configuration)
            nextLaunch = .demo(configuration)
        }

        public func useRegularApplicationOnNextLaunch() {
            inspectorModeController.useRegularApplicationOnNextLaunch()
            Self.clearDemo(in: userDefaults)
            nextLaunch = .regularApplication
        }

        /// Consume a demo only when the regular runtime is selected.
        public func consumeDemoConfiguration() -> DemoDataBuilder.Configuration? {
            guard case let .demo(configuration) = nextLaunch else { return nil }
            Self.clearDemo(in: userDefaults)
            nextLaunch = .regularApplication
            return configuration
        }

        /// Inspector recovery is authoritative and cancels a conflicting demo.
        @discardableResult
        public func completePendingStoreErasures(fileManager: FileManager) -> Bool {
            let completed = inspectorModeController.completePendingStoreErasures(
                fileManager: fileManager,
            )
            if !completed {
                scheduleInspector()
            }
            return completed
        }

        private func persistDemo(_ configuration: DemoDataBuilder.Configuration) {
            userDefaults.set(true, forKey: Self.demoEnabledKey)
            for category in DataIssueCategory.allCases {
                userDefaults.set(
                    configuration.issueCategories.contains(category),
                    forKey: Self.demoIssueKey(for: category),
                )
            }
        }

        private static func demoConfiguration(in userDefaults: UserDefaults)
            -> DemoDataBuilder.Configuration
        {
            DemoDataBuilder.Configuration(issueCategories: Set(
                DataIssueCategory.allCases.filter {
                    userDefaults.bool(forKey: demoIssueKey(for: $0))
                },
            ))
        }

        private static func clearDemo(in userDefaults: UserDefaults) {
            userDefaults.removeObject(forKey: demoEnabledKey)
            for category in DataIssueCategory.allCases {
                userDefaults.removeObject(forKey: demoIssueKey(for: category))
            }
        }

        private static func demoIssueKey(for category: DataIssueCategory) -> String {
            demoIssueKeyPrefix + category.rawValue
        }
    }
#endif
