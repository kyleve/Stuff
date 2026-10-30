import SwiftUI

/// Finite native transition timing. Document animation has its own bounded vocabulary.
public enum WhereThemeAnimation: Codable, Hashable, Sendable {
    case linear(duration: Double)
    case easeIn(duration: Double)
    case easeOut(duration: Double)
    case easeInOut(duration: Double)
    case spring(duration: Double, bounce: Double)

    var animation: Animation {
        switch self {
            case let .linear(duration): .linear(duration: duration)
            case let .easeIn(duration): .easeIn(duration: duration)
            case let .easeOut(duration): .easeOut(duration: duration)
            case let .easeInOut(duration): .easeInOut(duration: duration)
            case let .spring(duration, bounce): .spring(duration: duration, bounce: bounce)
        }
    }
}
