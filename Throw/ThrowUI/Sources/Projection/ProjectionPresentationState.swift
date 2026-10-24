import Foundation
import ThrowCore

/// One coordinator snapshot and the complete projection shown for its active identity.
enum ProjectionPresentationState: Equatable {
    struct Inactive: Equatable {
        let coordinator: ProjectionExperienceCoordinatorState
        let visible: VisibleProjection

        fileprivate init(
            coordinator: ProjectionExperienceCoordinatorState,
            visible: VisibleProjection,
        ) {
            self.coordinator = coordinator
            self.visible = visible
        }
    }

    struct AirAndSpace: Equatable {
        let coordinator: ProjectionExperienceCoordinatorState
        let visible: VisibleProjection.AirAndSpace

        fileprivate init(
            coordinator: ProjectionExperienceCoordinatorState,
            visible: VisibleProjection.AirAndSpace,
        ) {
            self.coordinator = coordinator
            self.visible = visible
        }
    }

    struct Transit: Equatable {
        let coordinator: ProjectionExperienceCoordinatorState
        let visible: VisibleProjection.Transit

        fileprivate init(
            coordinator: ProjectionExperienceCoordinatorState,
            visible: VisibleProjection.Transit,
        ) {
            self.coordinator = coordinator
            self.visible = visible
        }
    }

    #if DEBUG
        struct Testing: Equatable {
            let coordinator: ProjectionExperienceCoordinatorState
            let visible: VisibleProjection.Testing

            fileprivate init(
                coordinator: ProjectionExperienceCoordinatorState,
                visible: VisibleProjection.Testing,
            ) {
                self.coordinator = coordinator
                self.visible = visible
            }
        }
    #endif

    case inactive(Inactive)
    case airAndSpace(AirAndSpace)
    case transit(Transit)
    #if DEBUG
        case testing(Testing)
    #endif

    static func initial(
        coordinator: ProjectionExperienceCoordinatorState,
        preferredExperienceID: ProjectionExperienceID,
        mode: ProjectionMode,
        generatedAt: Date,
    ) -> Self {
        switch coordinator.activeExperienceID {
            case nil:
                return .inactive(Inactive(
                    coordinator: coordinator,
                    visible: .initial(
                        for: preferredExperienceID,
                        mode: mode,
                        generatedAt: generatedAt,
                    ),
                ))
            case .airAndSpace:
                return .airAndSpace(AirAndSpace(
                    coordinator: coordinator,
                    visible: .initial(mode: mode, generatedAt: generatedAt),
                ))
            case .transit:
                return .transit(Transit(
                    coordinator: coordinator,
                    visible: .initial(generatedAt: generatedAt),
                ))
            #if DEBUG
                case .testing:
                    return .testing(Testing(
                        coordinator: coordinator,
                        visible: .initial(mode: mode, generatedAt: generatedAt),
                    ))
            #endif
        }
    }

    var coordinator: ProjectionExperienceCoordinatorState {
        switch self {
            case let .inactive(state): state.coordinator
            case let .airAndSpace(state): state.coordinator
            case let .transit(state): state.coordinator
            #if DEBUG
                case let .testing(state): state.coordinator
            #endif
        }
    }

    var visible: VisibleProjection {
        switch self {
            case let .inactive(state): state.visible
            case let .airAndSpace(state): .airAndSpace(state.visible)
            case let .transit(state): .transit(state.visible)
            #if DEBUG
                case let .testing(state): .testing(state.visible)
            #endif
        }
    }

    func updatingCoordinator(
        _ coordinator: ProjectionExperienceCoordinatorState,
    ) -> Self? {
        guard let activeExperienceID = coordinator.activeExperienceID else {
            return .inactive(Inactive(coordinator: coordinator, visible: visible))
        }
        switch (self, activeExperienceID) {
            case let (.inactive(state), .airAndSpace):
                guard case let .airAndSpace(visible) = state.visible else { return nil }
                return .airAndSpace(AirAndSpace(coordinator: coordinator, visible: visible))
            case let (.inactive(state), .transit):
                guard case let .transit(visible) = state.visible else { return nil }
                return .transit(Transit(coordinator: coordinator, visible: visible))
            case let (.airAndSpace(state), .airAndSpace):
                return .airAndSpace(AirAndSpace(
                    coordinator: coordinator,
                    visible: state.visible,
                ))
            case let (.transit(state), .transit):
                return .transit(Transit(coordinator: coordinator, visible: state.visible))
            #if DEBUG
                case let (.inactive(state), .testing):
                    guard case let .testing(visible) = state.visible else { return nil }
                    return .testing(Testing(coordinator: coordinator, visible: visible))
                case let (.testing(state), .testing):
                    return .testing(Testing(coordinator: coordinator, visible: state.visible))
            #endif
            case (.inactive, _), (.airAndSpace, _), (.transit, _):
                return nil
            #if DEBUG
                case (.testing, _):
                    return nil
            #endif
        }
    }

    func replacingVisible(_ visible: VisibleProjection) -> Self? {
        switch (self, visible) {
            case let (.inactive(state), visible):
                return .inactive(Inactive(coordinator: state.coordinator, visible: visible))
            case let (.airAndSpace(state), .airAndSpace(visible)):
                return .airAndSpace(AirAndSpace(
                    coordinator: state.coordinator,
                    visible: visible,
                ))
            case let (.transit(state), .transit(visible)):
                return .transit(Transit(coordinator: state.coordinator, visible: visible))
            #if DEBUG
                case let (.testing(state), .testing(visible)):
                    return .testing(Testing(coordinator: state.coordinator, visible: visible))
            #endif
            case (.airAndSpace, _), (.transit, _):
                return nil
            #if DEBUG
                case (.testing, _):
                    return nil
            #endif
        }
    }

    static func committing(
        coordinator: ProjectionExperienceCoordinatorState,
        visible: VisibleProjection,
    ) -> Self? {
        switch (coordinator.activeExperienceID, visible) {
            case let (.none, visible):
                return .inactive(Inactive(coordinator: coordinator, visible: visible))
            case let (.airAndSpace, .airAndSpace(visible)):
                return .airAndSpace(AirAndSpace(coordinator: coordinator, visible: visible))
            case let (.transit, .transit(visible)):
                return .transit(Transit(coordinator: coordinator, visible: visible))
            #if DEBUG
                case let (.testing, .testing(visible)):
                    return .testing(Testing(coordinator: coordinator, visible: visible))
            #endif
            case (.airAndSpace, _), (.transit, _):
                return nil
            #if DEBUG
                case (.testing, _):
                    return nil
            #endif
        }
    }
}
