import SwiftUI

public enum WhereThemeTextAlignment: String, Codable, Hashable, Sendable {
    case leading, center, trailing
    var alignment: TextAlignment {
        switch self {
            case .leading: .leading
            case .center: .center
            case .trailing: .trailing
        }
    }
}
