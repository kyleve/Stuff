import LogKit
import SwiftUI

extension LogLevel {
    /// Short capitalized name shown in badges and the level filter.
    var displayName: String {
        switch self {
            case .debug: "Debug"
            case .info: "Info"
            case .notice: "Notice"
            case .warning: "Warning"
            case .error: "Error"
            case .fault: "Fault"
        }
    }

    /// Tint used for the level badge, escalating with severity.
    var tint: Color {
        switch self {
            case .debug: .gray
            case .info: .blue
            case .notice: .teal
            case .warning: .yellow
            case .error: .orange
            case .fault: .red
        }
    }
}
