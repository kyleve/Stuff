import BroadwayCore
import SwiftUI
import ViewDocumentCore
import ViewDocumentUI

extension WhereThemeAppearance {
    public enum ContentLayout: Codable, Hashable, Sendable {
        case inline
        case stacked
        var native: WhereStylesheet.ContentLayout {
            switch self {
                case .inline: .inline
                case .stacked: .stacked
            }
        }
    }
}
