import Foundation

/// Audience values resolved by the widget host and injected into WhereCore.
struct WhereWidgetBuildEnvironment {
    let appGroupIdentifier: String

    static func current(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
    ) -> WhereWidgetBuildEnvironment {
        let stampedAudience = requireString("WhereAudience", in: infoDictionary)
        precondition(
            stampedAudience == compiledAudience,
            "WhereAudience does not match the widget target's compiler condition",
        )
        return WhereWidgetBuildEnvironment(appGroupIdentifier: requireString(
            "WhereAppGroupIdentifier",
            in: infoDictionary,
        ))
    }

    private static func requireString(
        _ key: String,
        in infoDictionary: [String: Any],
    ) -> String {
        guard let value = infoDictionary[key] as? String, !value.isEmpty else {
            preconditionFailure("WhereWidgets' Info.plist has no non-empty \(key)")
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
        private static let compiledAudience = "development"
    #elseif WHERE_BETA
        private static let compiledAudience = "beta"
    #elseif WHERE_APP_STORE
        private static let compiledAudience = "appStore"
    #else
        #error("A Where audience compiler condition must be active")
    #endif
}
