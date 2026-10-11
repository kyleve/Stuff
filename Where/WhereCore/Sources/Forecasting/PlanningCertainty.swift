import Foundation

/// Whether every endpoint choice or only some choices include a projected day.
public enum PlanningCertainty: Hashable, Sendable {
    case certain
    case possible
}
