import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

func projectionTestObserver(latitude: Double, longitude: Double) throws -> ObserverPosition {
    try ObserverPosition(
        coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
        altitude: Altitude(feet: 100),
    )
}

func projectionTestAirFrame(observedAt: Date) -> AirAndSpaceExperienceFrame {
    AirAndSpaceExperienceFrame(
        geography: nil,
        flights: ProjectionLayerFrame<FlightsLayerKind>.empty(observedAt: observedAt),
        stars: nil,
        satellites: nil,
    )
}

func projectionTestAirOutput(
    semanticFrame: AirAndSpaceExperienceFrame,
    observer: ObserverPosition,
    generatedAt: Date,
    revision: UInt64,
    observerPoint: ProjectionPoint?,
) throws -> ProjectionFrameWorkerOutput {
    let request = ProjectionFrameRequest.airAndSpace(.init(
        input: AirAndSpaceProjectionInput(
            frame: semanticFrame,
            viewport: .map(viewport: .defaultValue, geography: .hidden),
        ),
        context: ProjectionFrameRequest.Context(
            observer: observer,
            mapCenter: observer.coordinate,
            calibration: .defaultValue,
            reduceMotion: false,
            loggingOperation: .projectionRendering,
        ),
        generatedAt: generatedAt,
        revision: .init(rawValue: revision),
    ))
    return try #require(ProjectionFrameWorkerOutput(
        request: request,
        render: .init(
            frame: .emptyAirAndSpace(mode: .map, generatedAt: generatedAt),
            geographyHealth: .idle,
            effects: [:],
            observerPoint: observerPoint,
        ),
    ))
}

func projectionTestTransitOutput(
    observer: ObserverPosition,
    generatedAt: Date,
    revision: UInt64,
) throws -> ProjectionFrameWorkerOutput {
    let request = ProjectionFrameRequest.transit(.init(
        input: TransitProjectionInput(
            frame: .empty,
            viewport: .defaultValue,
            geography: .hidden,
        ),
        context: ProjectionFrameRequest.Context(
            observer: observer,
            mapCenter: observer.coordinate,
            calibration: .defaultValue,
            reduceMotion: false,
            loggingOperation: .projectionRendering,
        ),
        generatedAt: generatedAt,
        revision: .init(rawValue: revision),
    ))
    return try #require(ProjectionFrameWorkerOutput(
        request: request,
        render: .init(
            frame: .emptyTransit(generatedAt: generatedAt),
            geographyHealth: .idle,
            effects: [:],
            observerPoint: nil,
        ),
    ))
}

func projectionTestCoordinator(
    activeExperienceID: ProjectionExperienceID?,
) -> ProjectionExperienceCoordinatorState {
    ProjectionExperienceCoordinatorState(
        activeExperienceID: activeExperienceID,
        requestedExperienceID: nil,
        prewarmingExperienceID: nil,
        isPaused: false,
        dwellEndsAt: nil,
        nextExperienceID: nil,
        healthByExperience: [:],
        manualSelectionFailure: nil,
    )
}
