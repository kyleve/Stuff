import ThrowCore

/// A rendered frame that retains the exact typed request and render metadata that produced it.
enum ProjectionFrameWorkerOutput: Equatable {
    struct RenderMetadata: Equatable {
        let frame: ProjectionFrame
        let geographyHealth: GeographyLayerHealth
        let effects: [LayerMarkID: ProjectionMarkEffect]
        let observerPoint: ProjectionPoint?

        func replacingFrame(
            _ frame: ProjectionFrame,
            geographyHealth: GeographyLayerHealth? = nil,
            effects: [LayerMarkID: ProjectionMarkEffect]? = nil,
        ) -> Self {
            Self(
                frame: frame,
                geographyHealth: geographyHealth ?? self.geographyHealth,
                effects: effects ?? self.effects,
                observerPoint: observerPoint,
            )
        }
    }

    struct AirAndSpace: Equatable {
        let request: ProjectionFrameRequest.AirAndSpace
        let render: RenderMetadata

        fileprivate init(
            request: ProjectionFrameRequest.AirAndSpace,
            render: RenderMetadata,
        ) {
            self.request = request
            self.render = render
        }

        func replacingFrame(
            _ frame: ProjectionFrame,
            geographyHealth: GeographyLayerHealth? = nil,
            effects: [LayerMarkID: ProjectionMarkEffect]? = nil,
        ) -> Self? {
            guard frame.productionExperienceID == .airAndSpace else { return nil }
            return Self(
                request: request,
                render: render.replacingFrame(
                    frame,
                    geographyHealth: geographyHealth,
                    effects: effects,
                ),
            )
        }
    }

    struct Transit: Equatable {
        let request: ProjectionFrameRequest.Transit
        let render: RenderMetadata

        fileprivate init(
            request: ProjectionFrameRequest.Transit,
            render: RenderMetadata,
        ) {
            self.request = request
            self.render = render
        }

        func replacingFrame(
            _ frame: ProjectionFrame,
            geographyHealth: GeographyLayerHealth? = nil,
            effects: [LayerMarkID: ProjectionMarkEffect]? = nil,
        ) -> Self? {
            guard frame.productionExperienceID == .transit else { return nil }
            return Self(
                request: request,
                render: render.replacingFrame(
                    frame,
                    geographyHealth: geographyHealth,
                    effects: effects,
                ),
            )
        }
    }

    #if DEBUG
        struct Testing: Equatable {
            let request: ProjectionFrameRequest.Testing
            let render: RenderMetadata
        }
    #endif

    case airAndSpace(AirAndSpace)
    case transit(Transit)
    #if DEBUG
        case testing(Testing)
    #endif

    init?(request: ProjectionFrameRequest, render: RenderMetadata) {
        switch request {
            case let .airAndSpace(request):
                guard render.frame.productionExperienceID == .airAndSpace else { return nil }
                self = .airAndSpace(AirAndSpace(request: request, render: render))
            case let .transit(request):
                guard render.frame.productionExperienceID == .transit else { return nil }
                self = .transit(Transit(request: request, render: render))
            #if DEBUG
                case let .testing(request):
                    self = .testing(Testing(request: request, render: render))
            #endif
        }
    }

    var request: ProjectionFrameRequest {
        switch self {
            case let .airAndSpace(output): .airAndSpace(output.request)
            case let .transit(output): .transit(output.request)
            #if DEBUG
                case let .testing(output): .testing(output.request)
            #endif
        }
    }

    var frame: ProjectionFrame {
        render.frame
    }

    var geographyHealth: GeographyLayerHealth {
        render.geographyHealth
    }

    var effects: [LayerMarkID: ProjectionMarkEffect] {
        render.effects
    }

    var observerPoint: ProjectionPoint? {
        render.observerPoint
    }

    var experienceID: ProjectionExperienceID {
        request.experienceID
    }

    var semanticFrame: ProjectionExperienceFrame? {
        switch self {
            case let .airAndSpace(output): .airAndSpace(output.request.input.frame)
            case let .transit(output): .transit(output.request.input.frame)
            #if DEBUG
                case .testing: nil
            #endif
        }
    }

    var context: ProjectionFrameRequest.Context {
        request.context
    }

    var revision: ProjectionFrameRequest.Revision {
        request.revision
    }

    private var render: RenderMetadata {
        switch self {
            case let .airAndSpace(output): output.render
            case let .transit(output): output.render
            #if DEBUG
                case let .testing(output): output.render
            #endif
        }
    }
}
