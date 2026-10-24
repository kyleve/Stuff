import Foundation
import ThrowCore

/// One complete renderer publication with a compile-time experience and semantic pairing.
enum VisibleProjection: Equatable {
    struct AirAndSpace: Equatable {
        struct Placeholder: Equatable {
            let activationLease: ProjectionActivationLease?
            let mode: ProjectionMode
            let generatedAt: Date
        }

        enum Content: Equatable {
            case placeholder(Placeholder)
            case rendered(
                activationLease: ProjectionActivationLease,
                output: ProjectionFrameWorkerOutput.AirAndSpace,
            )
            #if DEBUG
                case fixture(Fixture)
            #endif
        }

        #if DEBUG
            struct Fixture: Equatable {
                let activationLease: ProjectionActivationLease?
                let frame: ProjectionFrame
                let effects: [LayerMarkID: ProjectionMarkEffect]
                let observerPoint: ProjectionPoint?
                let geographyHealth: GeographyLayerHealth
            }
        #endif

        fileprivate let content: Content

        static func initial(mode: ProjectionMode, generatedAt: Date) -> Self {
            Self(content: .placeholder(.init(
                activationLease: nil,
                mode: mode,
                generatedAt: generatedAt,
            )))
        }
    }

    struct Transit: Equatable {
        struct Placeholder: Equatable {
            let activationLease: ProjectionActivationLease?
            let generatedAt: Date
        }

        enum Content: Equatable {
            case placeholder(Placeholder)
            case rendered(
                activationLease: ProjectionActivationLease,
                output: ProjectionFrameWorkerOutput.Transit,
            )
            #if DEBUG
                case fixture(Fixture)
            #endif
        }

        #if DEBUG
            struct Fixture: Equatable {
                let activationLease: ProjectionActivationLease?
                let frame: ProjectionFrame
                let effects: [LayerMarkID: ProjectionMarkEffect]
                let observerPoint: ProjectionPoint?
                let geographyHealth: GeographyLayerHealth
            }
        #endif

        fileprivate let content: Content

        static func initial(generatedAt: Date) -> Self {
            Self(content: .placeholder(.init(
                activationLease: nil,
                generatedAt: generatedAt,
            )))
        }
    }

    #if DEBUG
        struct Testing: Equatable {
            let frame: ProjectionFrame
            let effects: [LayerMarkID: ProjectionMarkEffect]
            let observerPoint: ProjectionPoint?
            let geographyHealth: GeographyLayerHealth

            static func initial(mode: ProjectionMode, generatedAt: Date) -> Self {
                Self(
                    frame: .testing(
                        experienceID: .testing,
                        mode: mode,
                        generatedAt: generatedAt,
                        layers: [],
                    ),
                    effects: [:],
                    observerPoint: nil,
                    geographyHealth: .idle,
                )
            }
        }
    #endif

    case airAndSpace(AirAndSpace)
    case transit(Transit)
    #if DEBUG
        case testing(Testing)
    #endif

    static func initial(
        for experienceID: ProjectionExperienceID,
        mode: ProjectionMode,
        generatedAt: Date,
    ) -> Self {
        switch experienceID {
            case .airAndSpace:
                return .airAndSpace(AirAndSpace.initial(
                    mode: mode,
                    generatedAt: generatedAt,
                ))
            case .transit:
                return .transit(Transit.initial(generatedAt: generatedAt))
            #if DEBUG
                case .testing:
                    return .testing(Testing.initial(mode: mode, generatedAt: generatedAt))
            #endif
        }
    }

    static func rendered(
        activationLease: ProjectionActivationLease,
        output: ProjectionFrameWorkerOutput,
    ) -> Self? {
        switch activationLease.runnableExperienceID {
            case .airAndSpace:
                guard case let .airAndSpace(output) = output else { return nil }
                return .airAndSpace(AirAndSpace(content: .rendered(
                    activationLease: activationLease,
                    output: output,
                )))
            case .transit:
                guard case let .transit(output) = output else { return nil }
                return .transit(Transit(content: .rendered(
                    activationLease: activationLease,
                    output: output,
                )))
            #if DEBUG
                case .testing(.transit):
                    guard case let .transit(output) = output else { return nil }
                    return .transit(Transit(content: .rendered(
                        activationLease: activationLease,
                        output: output,
                    )))
                case .testing:
                    return nil
            #endif
        }
    }

    #if DEBUG
        static func fixture(output: ProjectionFrameWorkerOutput) -> Self {
            switch output {
                case let .airAndSpace(output):
                    .airAndSpace(AirAndSpace(content: .fixture(.init(
                        activationLease: nil,
                        frame: output.render.frame,
                        effects: output.render.effects,
                        observerPoint: output.render.observerPoint,
                        geographyHealth: output.render.geographyHealth,
                    ))))
                case let .transit(output):
                    .transit(Transit(content: .fixture(.init(
                        activationLease: nil,
                        frame: output.render.frame,
                        effects: output.render.effects,
                        observerPoint: output.render.observerPoint,
                        geographyHealth: output.render.geographyHealth,
                    ))))
                case let .testing(output):
                    .testing(Testing(
                        frame: output.render.frame,
                        effects: output.render.effects,
                        observerPoint: output.render.observerPoint,
                        geographyHealth: output.render.geographyHealth,
                    ))
            }
        }
    #endif

    var experienceID: ProjectionExperienceID {
        switch self {
            case .airAndSpace: .airAndSpace
            case .transit: .transit
            #if DEBUG
                case let .testing(presentation): presentation.frame.experienceID
            #endif
        }
    }

    var activationLease: ProjectionActivationLease? {
        switch self {
            case let .airAndSpace(presentation):
                presentation.content.activationLease
            case let .transit(presentation):
                presentation.content.activationLease
            #if DEBUG
                case .testing: nil
            #endif
        }
    }

    var semanticFrame: ProjectionExperienceFrame? {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder: .airAndSpace(.empty)
                    case let .rendered(_, output): .airAndSpace(output.request.input.frame)
                    #if DEBUG
                        case .fixture: .airAndSpace(.empty)
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder: .transit(.empty)
                    case let .rendered(_, output): .transit(output.request.input.frame)
                    #if DEBUG
                        case .fixture: .transit(.empty)
                    #endif
                }
            #if DEBUG
                case .testing: nil
            #endif
        }
    }

    var frame: ProjectionFrame {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case let .placeholder(placeholder):
                        .emptyAirAndSpace(
                            mode: placeholder.mode,
                            generatedAt: placeholder.generatedAt,
                        )
                    case let .rendered(_, output): output.render.frame
                    #if DEBUG
                        case let .fixture(fixture): fixture.frame
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case let .placeholder(placeholder):
                        .emptyTransit(generatedAt: placeholder.generatedAt)
                    case let .rendered(_, output): output.render.frame
                    #if DEBUG
                        case let .fixture(fixture): fixture.frame
                    #endif
                }
            #if DEBUG
                case let .testing(presentation): presentation.frame
            #endif
        }
    }

    var effects: [LayerMarkID: ProjectionMarkEffect] {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder: [:]
                    case let .rendered(_, output): output.render.effects
                    #if DEBUG
                        case let .fixture(fixture): fixture.effects
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder: [:]
                    case let .rendered(_, output): output.render.effects
                    #if DEBUG
                        case let .fixture(fixture): fixture.effects
                    #endif
                }
            #if DEBUG
                case let .testing(presentation): presentation.effects
            #endif
        }
    }

    var observerPoint: ProjectionPoint? {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder: nil
                    case let .rendered(_, output): output.render.observerPoint
                    #if DEBUG
                        case let .fixture(fixture): fixture.observerPoint
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder: nil
                    case let .rendered(_, output): output.render.observerPoint
                    #if DEBUG
                        case let .fixture(fixture): fixture.observerPoint
                    #endif
                }
            #if DEBUG
                case let .testing(presentation): presentation.observerPoint
            #endif
        }
    }

    var geographyHealth: GeographyLayerHealth {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder: .idle
                    case let .rendered(_, output): output.render.geographyHealth
                    #if DEBUG
                        case let .fixture(fixture): fixture.geographyHealth
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder: .idle
                    case let .rendered(_, output): output.render.geographyHealth
                    #if DEBUG
                        case let .fixture(fixture): fixture.geographyHealth
                    #endif
                }
            #if DEBUG
                case let .testing(presentation): presentation.geographyHealth
            #endif
        }
    }

    var request: ProjectionFrameRequest? {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder: nil
                    case let .rendered(_, output): .airAndSpace(output.request)
                    #if DEBUG
                        case .fixture: nil
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder: nil
                    case let .rendered(_, output): .transit(output.request)
                    #if DEBUG
                        case .fixture: nil
                    #endif
                }
            #if DEBUG
                case .testing: nil
            #endif
        }
    }

    func cleared(mode: ProjectionMode, generatedAt: Date) -> Self {
        switch self {
            case let .airAndSpace(presentation):
                return .airAndSpace(AirAndSpace(content: .placeholder(.init(
                    activationLease: presentation.content.activationLease,
                    mode: mode,
                    generatedAt: generatedAt,
                ))))
            case let .transit(presentation):
                return .transit(Transit(content: .placeholder(.init(
                    activationLease: presentation.content.activationLease,
                    generatedAt: generatedAt,
                ))))
            #if DEBUG
                case .testing:
                    return .testing(Testing.initial(mode: mode, generatedAt: generatedAt))
            #endif
        }
    }

    func removingGeography() -> Self {
        replacingRenderedFrame(
            frame.removingGeography(),
            geographyHealth: .idle,
        )
    }

    func withoutMarks(generatedAt: Date) -> Self {
        replacingRenderedFrame(
            frame.withoutMarks(generatedAt: generatedAt),
            effects: [:],
        )
    }

    private func replacingRenderedFrame(
        _ frame: ProjectionFrame,
        geographyHealth: GeographyLayerHealth? = nil,
        effects: [LayerMarkID: ProjectionMarkEffect]? = nil,
    ) -> Self {
        switch self {
            case let .airAndSpace(presentation):
                switch presentation.content {
                    case .placeholder:
                        return self
                    case let .rendered(activationLease, output):
                        guard let output = output.replacingFrame(
                            frame,
                            geographyHealth: geographyHealth,
                            effects: effects,
                        ) else {
                            assertionFailure("An Air & Space edit must preserve its frame type")
                            return self
                        }
                        return .airAndSpace(AirAndSpace(content: .rendered(
                            activationLease: activationLease,
                            output: output,
                        )))
                    #if DEBUG
                        case let .fixture(fixture):
                            return .airAndSpace(AirAndSpace(content: .fixture(.init(
                                activationLease: fixture.activationLease,
                                frame: frame,
                                effects: effects ?? fixture.effects,
                                observerPoint: fixture.observerPoint,
                                geographyHealth: geographyHealth ?? fixture.geographyHealth,
                            ))))
                    #endif
                }
            case let .transit(presentation):
                switch presentation.content {
                    case .placeholder:
                        return self
                    case let .rendered(activationLease, output):
                        guard let output = output.replacingFrame(
                            frame,
                            geographyHealth: geographyHealth,
                            effects: effects,
                        ) else {
                            assertionFailure("A Transit edit must preserve its frame type")
                            return self
                        }
                        return .transit(Transit(content: .rendered(
                            activationLease: activationLease,
                            output: output,
                        )))
                    #if DEBUG
                        case let .fixture(fixture):
                            return .transit(Transit(content: .fixture(.init(
                                activationLease: fixture.activationLease,
                                frame: frame,
                                effects: effects ?? fixture.effects,
                                observerPoint: fixture.observerPoint,
                                geographyHealth: geographyHealth ?? fixture.geographyHealth,
                            ))))
                    #endif
                }
            #if DEBUG
                case let .testing(presentation):
                    return .testing(Testing(
                        frame: frame,
                        effects: presentation.effects,
                        observerPoint: presentation.observerPoint,
                        geographyHealth: geographyHealth ?? presentation.geographyHealth,
                    ))
            #endif
        }
    }

    #if DEBUG
        func replacingFrameForTesting(_ frame: ProjectionFrame) -> Self? {
            switch (self, frame.experienceID) {
                case let (.airAndSpace(presentation), .airAndSpace):
                    .airAndSpace(AirAndSpace(content: .fixture(.init(
                        activationLease: presentation.content.activationLease,
                        frame: frame,
                        effects: effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))))
                case let (.transit(presentation), .transit):
                    .transit(Transit(content: .fixture(.init(
                        activationLease: presentation.content.activationLease,
                        frame: frame,
                        effects: effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))))
                case (.testing, .testing):
                    .testing(Testing(
                        frame: frame,
                        effects: effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))
                case (.airAndSpace, _), (.transit, _), (.testing, _): nil
            }
        }

        func replacingMetadataForTesting(
            observerPoint: ProjectionPoint?,
            geographyHealth: GeographyLayerHealth,
        ) -> Self {
            switch self {
                case let .airAndSpace(presentation):
                    .airAndSpace(AirAndSpace(content: .fixture(.init(
                        activationLease: presentation.content.activationLease,
                        frame: frame,
                        effects: effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))))
                case let .transit(presentation):
                    .transit(Transit(content: .fixture(.init(
                        activationLease: presentation.content.activationLease,
                        frame: frame,
                        effects: effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))))
                case let .testing(presentation):
                    .testing(Testing(
                        frame: presentation.frame,
                        effects: presentation.effects,
                        observerPoint: observerPoint,
                        geographyHealth: geographyHealth,
                    ))
            }
        }
    #endif
}

extension VisibleProjection.AirAndSpace.Content {
    fileprivate var activationLease: ProjectionActivationLease? {
        switch self {
            case let .placeholder(placeholder): placeholder.activationLease
            case let .rendered(activationLease, _): activationLease
            #if DEBUG
                case let .fixture(fixture): fixture.activationLease
            #endif
        }
    }
}

extension VisibleProjection.Transit.Content {
    fileprivate var activationLease: ProjectionActivationLease? {
        switch self {
            case let .placeholder(placeholder): placeholder.activationLease
            case let .rendered(activationLease, _): activationLease
            #if DEBUG
                case let .fixture(fixture): fixture.activationLease
            #endif
        }
    }
}
