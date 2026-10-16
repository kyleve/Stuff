import Observation

/// One presentation owner for the calendar and timeline, retained above adaptive containers.
@MainActor @Observable
final class PlanningPresentationModel {
    var destination: PlannedStaysDestination?
}
