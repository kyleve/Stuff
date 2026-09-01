import Foundation
#if DEBUG
    @_spi(Testing) import ThrowCore
#else
    import ThrowCore
#endif

/// One immutable semantic revision and projection context sent to the render actor.
enum ProjectionFrameRequest: Equatable {
    /// The monotonic identity of inputs that can change a visible projection.
    struct Revision: Equatable {
        static let initial = Revision(rawValue: 0)

        let rawValue: UInt64

        func successor() -> Revision {
            precondition(rawValue < UInt64.max, "A projection revision must not overflow")
            return Revision(rawValue: rawValue + 1)
        }
    }

    /// Values outside a semantic frame that determine its projected geometry.
    struct Context: Equatable {
        let observer: ObserverPosition
        let mapCenter: GeoCoordinate
        let calibration: ProjectionCalibration
        let reduceMotion: Bool
        let loggingOperation: ThrowSessionLogEvent.PostLaunchOperation
    }

    struct AirAndSpace: Equatable {
        let input: AirAndSpaceProjectionInput
        let context: Context
        let generatedAt: Date
        let revision: Revision
    }

    struct Transit: Equatable {
        let input: TransitProjectionInput
        let context: Context
        let generatedAt: Date
        let revision: Revision
    }

    #if DEBUG
        struct Testing: Equatable {
            let experienceID: ProjectionExperienceID
            let layerFrames: [LayerFrame]
            let geographyEnabled: Bool
            let viewport: ProjectionViewport
            let context: Context
            let generatedAt: Date
            let revision: Revision
        }
    #endif

    case airAndSpace(AirAndSpace)
    case transit(Transit)
    #if DEBUG
        case testing(Testing)
    #endif

    var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
            #if DEBUG
                case let .testing(request): request.experienceID
            #endif
        }
    }

    var context: Context {
        switch self {
            case let .airAndSpace(request): request.context
            case let .transit(request): request.context
            #if DEBUG
                case let .testing(request): request.context
            #endif
        }
    }

    var generatedAt: Date {
        switch self {
            case let .airAndSpace(request): request.generatedAt
            case let .transit(request): request.generatedAt
            #if DEBUG
                case let .testing(request): request.generatedAt
            #endif
        }
    }

    var revision: Revision {
        switch self {
            case let .airAndSpace(request): request.revision
            case let .transit(request): request.revision
            #if DEBUG
                case let .testing(request): request.revision
            #endif
        }
    }

    var viewport: ProjectionViewport {
        switch self {
            case let .airAndSpace(request): request.input.viewport.viewport
            case let .transit(request): .map(request.input.viewport)
            #if DEBUG
                case let .testing(request): request.viewport
            #endif
        }
    }

    var requestsGeography: Bool {
        switch self {
            case let .airAndSpace(request): request.input.viewport.requestsGeography
            case let .transit(request): request.input.geography == .visible
            #if DEBUG
                case let .testing(request): request.geographyEnabled
            #endif
        }
    }

    var flightsFrame: ProjectionLayerFrame<FlightsLayerKind>? {
        switch self {
            case let .airAndSpace(request):
                return request.input.frame.flights
            case .transit:
                return nil
            #if DEBUG
                case let .testing(request):
                    guard let frame = request.layerFrames.first(where: {
                        $0.layerID == .flights
                    }) else { return nil }
                    return ProjectionLayerFrame(
                        observedAt: frame.observedAt,
                        marks: frame.marks,
                    )
            #endif
        }
    }

    var markRevisions: [LayerID: Date] {
        switch self {
            case let .airAndSpace(request):
                let frame = request.input.frame
                var revisions: [LayerID: Date] = [:]
                revisions[.flights] = frame.flights?.observedAt
                revisions[.stars] = frame.stars?.observedAt
                revisions[.satellites] = frame.satellites?.observedAt
                return revisions
            case let .transit(request):
                return request.input.frame.vehicles.map {
                    [.transitVehicles: $0.observedAt]
                } ?? [:]
            #if DEBUG
                case let .testing(request):
                    var revisions: [LayerID: Date] = [:]
                    for frame in request.layerFrames {
                        if case .marks = frame.content {
                            revisions[frame.layerID] = frame.observedAt
                        }
                    }
                    return revisions
            #endif
        }
    }
}
