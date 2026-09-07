import Foundation

extension OutputHealth {
    var localizedDescription: String {
        switch self {
            case .disconnected: String(localized: .statusDisconnected)
            case .preview: String(localized: .dashboardPreview)
            case .externalDisplay: String(localized: .outputExternalDisplay)
            case .fullScreen: String(localized: .outputFullScreen)
            case .multiple:
                String(localized: .outputMultiple)
        }
    }
}
