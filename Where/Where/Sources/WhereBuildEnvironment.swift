import Foundation
import WhereCore

/// Audience-specific values selected by this host target's compiler condition.
///
/// Only the app and extension targets see `WHERE_*`; package modules receive
/// the concrete App Group, storage, and presentation values produced here.
struct WhereBuildEnvironment: Equatable {
    enum Audience: String, Equatable {
        case development
        case beta
        case appStore
    }

    let audience: Audience
    let appGroupIdentifier: String
    let primaryAppIconName: String
    let isRunningTests: Bool

    var storage: SwiftDataStore.Storage {
        storage(forCloudKitValidationBuild: false)
    }

    func storage(
        forCloudKitValidationBuild validatesCloudKit: Bool,
    ) -> SwiftDataStore.Storage {
        if isRunningTests {
            return .inMemory
        }
        switch audience {
            case .development:
                return validatesCloudKit
                    ? .cloudKit(appGroupIdentifier: appGroupIdentifier)
                    : .localOnly(appGroupIdentifier: appGroupIdentifier)
            case .beta, .appStore:
                return .cloudKit(appGroupIdentifier: appGroupIdentifier)
        }
    }

    func makeWidgetRefresher() -> any WidgetTimelineRefreshing {
        if isRunningTests {
            NoopWidgetTimelineRefresher()
        } else {
            WidgetCenterTimelineRefresher(appGroupIdentifier: appGroupIdentifier)
        }
    }

    static func current(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> WhereBuildEnvironment {
        let audience = compiledAudience
        let stampedAudience = requireString("WhereAudience", in: infoDictionary)
        precondition(
            stampedAudience == audience.rawValue,
            "WhereAudience does not match the target's compiler condition",
        )
        return WhereBuildEnvironment(
            audience: audience,
            appGroupIdentifier: requireString(
                "WhereAppGroupIdentifier",
                in: infoDictionary,
            ),
            primaryAppIconName: requireString(
                "WherePrimaryAppIconName",
                in: infoDictionary,
            ),
            isRunningTests: processEnvironment["XCTestConfigurationFilePath"] != nil,
        )
    }

    private static func requireString(
        _ key: String,
        in infoDictionary: [String: Any],
    ) -> String {
        guard let value = infoDictionary[key] as? String, !value.isEmpty else {
            preconditionFailure("Where's Info.plist has no non-empty \(key)")
        }
        return value
    }

    #if WHERE_DEVELOPMENT && WHERE_BETA
        #error("Exactly one Where audience compiler condition must be active")
    #endif
    #if WHERE_DEVELOPMENT && WHERE_APP_STORE
        #error("Exactly one Where audience compiler condition must be active")
    #endif
    #if WHERE_BETA && WHERE_APP_STORE
        #error("Exactly one Where audience compiler condition must be active")
    #endif

    #if WHERE_DEVELOPMENT
        private static let compiledAudience = Audience.development
    #elseif WHERE_BETA
        private static let compiledAudience = Audience.beta
    #elseif WHERE_APP_STORE
        private static let compiledAudience = Audience.appStore
    #else
        #error("A Where audience compiler condition must be active")
    #endif
}
