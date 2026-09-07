import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

struct ThrowProjectRulesTests {
    @Test func sessionConstructionStaysAtItsCompositionRoot() throws {
        let allowed = try evaluate(
            path: "Throw/ThrowUI/Sources/Model/ThrowSession+Composition.swift",
            component: .throwUI,
            source: "func live() { _ = ThrowSession() }",
        )
        let rejected = try evaluate(
            path: "Throw/ThrowUI/Sources/Model/CompetingSession.swift",
            component: .throwUI,
            source: "func live() { _ = ThrowSession() }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(
            rejected.violations.map(\.rule.id) == ["throw.session_composition_ownership"],
        )
    }

    @Test func runtimeConstructionStaysAtItsAppOwner() throws {
        let allowed = try evaluate(
            path: "Throw/Throw/Sources/ThrowRuntime.swift",
            component: .throwApp,
            source: "func live() { _ = ThrowRuntime() }",
        )
        let rejected = try evaluate(
            path: "Throw/Throw/Sources/ExternalDisplaySceneDelegate.swift",
            component: .throwApp,
            source: "func fallback() { _ = ThrowRuntime() }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(
            rejected.violations.map(\.rule.id) == ["throw.runtime_composition_ownership"],
        )
    }

    @Test func liveDependenciesStayAtTheSessionCompositionRoot() throws {
        let source = """
        func live() {
            _ = AircraftPollingCoordinator()
            _ = AircraftSourceFactory()
            _ = AircraftSourceService()
            _ = CoreLocationThrowSource()
            _ = KeychainAircraftCredentialStore()
            _ = PeriscopeThrowDurableLoggingStarter()
            _ = UserDefaultsThrowPreferenceStore()
        }
        """
        let allowed = try evaluate(
            path: "Throw/ThrowUI/Sources/Model/ThrowSession+Composition.swift",
            component: .throwUI,
            source: source,
        )
        let rejected = try evaluate(
            path: "Throw/ThrowUI/Sources/Model/CompetingLiveGraph.swift",
            component: .throwUI,
            source: source,
        )

        #expect(allowed.violations.isEmpty)
        #expect(rejected.violations.count == 7)
        #expect(rejected.violations.allSatisfy {
            $0.rule.id == "throw.live_dependency_composition_ownership"
        })
    }

    @Test func rawLayerFramesStayAtTheCoreErasureBoundary() throws {
        let allowed = try evaluate(
            path: "Throw/ThrowCore/Sources/ProjectionModels.swift",
            component: .throwCore,
            source: "func erase() { _ = LayerFrame() }",
        )
        let rejected = try evaluate(
            path: "Throw/ThrowUI/Sources/Model/LooseLayer.swift",
            component: .throwUI,
            source: "func erase() { _ = LayerFrame() }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(
            rejected.violations.map(\.rule.id) == ["throw.layer_frame_erasure_ownership"],
        )
    }

    @Test func projectedFramesEraseOnlyAtThePresentationBoundary() throws {
        let source = "func erase() { _ = ProjectedLayer(); _ = ProjectionFrame() }"
        let allowed = try evaluate(
            path: "Throw/ThrowUI/Sources/Projection/ProjectionFrame.swift",
            component: .throwUI,
            source: source,
        )
        let rejected = try evaluate(
            path: "Throw/ThrowUI/Sources/Projection/ProjectionFrameWorker.swift",
            component: .throwUI,
            source: source,
        )

        #expect(allowed.violations.isEmpty)
        #expect(rejected.violations.count == 2)
        #expect(rejected.violations.allSatisfy {
            $0.rule.id == "throw.projected_frame_erasure_ownership"
        })
    }

    @Test func projectionFamiliesStayTypedThroughThePresentationBoundary() throws {
        let coreAllowed = try evaluate(
            path: "Throw/ThrowCore/Sources/ProjectionModels.swift",
            component: .throwCore,
            source: """
            enum StarsLayerKind { typealias MarkElement = StarMarkElement }
            enum GeographyLayerKind { typealias LineStyle = GeographyLineKind }
            enum FlightsMarkElement { case airport(AirportGlyphDescriptor) }
            """,
        )
        let coreRejected = try evaluate(
            path: "Throw/ThrowCore/Sources/ProjectionModels.swift",
            component: .throwCore,
            source: """
            enum StarsLayerKind { typealias MarkElement = FlightsMarkElement }
            enum GeographyLayerKind { typealias LineStyle = TransitNetworkLineStyle }
            enum FlightsMarkElement {
                case airport(AirportID, AirportGlyphDescriptor)
            }
            """,
        )
        let presentationAllowed = try evaluate(
            path: "Throw/ThrowUI/Sources/Projection/ProjectionFrame.swift",
            component: .throwUI,
            source: "func updatingMarkPresentation(fieldsByID: [ID: Fields]) {}",
        )
        let presentationRejected = try evaluate(
            path: "Throw/ThrowUI/Sources/Projection/ProjectionFrame.swift",
            component: .throwUI,
            source: "func replacingMarks(_ marks: [PresentedMark]) {}",
        )

        #expect(coreAllowed.violations.isEmpty)
        #expect(coreRejected.violations.count == 3)
        #expect(coreRejected.violations.allSatisfy {
            $0.rule.id == "throw.typed_projection_families"
        })
        #expect(presentationAllowed.violations.isEmpty)
        #expect(
            presentationRejected.violations.map(\.rule.id) ==
                ["throw.typed_projection_families"],
        )
    }

    @Test func productionViewsKeepConcreteTypes() throws {
        let allowed = try evaluate(
            path: "Throw/Throw/Sources/ConcreteRoot.swift",
            component: .throwApp,
            source: "struct ConcreteRoot: View { var body: some View { Text(\"Throw\") } }",
        )
        let rejected = try evaluate(
            path: "Throw/Throw/Sources/ErasedRoot.swift",
            component: .throwApp,
            source: "func root() -> AnyView { AnyView(Text(\"Throw\")) }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(rejected.violations.allSatisfy { $0.rule.id == "throw.no_any_view" })
        #expect(rejected.violations.isEmpty == false)
    }

    @Test func productionLoggingUsesTypedFacade() throws {
        let allowed = try evaluate(
            path: "Throw/ThrowCore/Sources/Worker.swift",
            component: .throwCore,
            source: "func run() { ThrowLog.session { .durableLoggingReady } }",
        )
        let printRejected = try evaluate(
            path: "Throw/ThrowUI/Sources/PrintingWorker.swift",
            component: .throwUI,
            source: "func run() { print(\"done\") }",
        )
        let osLogRejected = try evaluate(
            path: "Throw/Throw/Sources/LoggingShell.swift",
            component: .throwApp,
            source: "import os\nstruct LoggingShell {}",
        )

        #expect(allowed.violations.isEmpty)
        #expect(printRejected.violations.map(\.rule.id) == ["throw.logging_facade"])
        #expect(osLogRejected.violations.map(\.rule.id) == ["throw.logging_facade"])
    }

    @Test func providerImplementationsStayInCore() throws {
        let allowed = try evaluate(
            path: "Throw/ThrowCore/Sources/SourceService.swift",
            component: .throwCore,
            source: "func make() { _ = Flightradar24Source.self }",
        )
        let rejected = try evaluate(
            path: "Throw/ThrowUI/Sources/SourceSettings.swift",
            component: .throwUI,
            source: "func make() { _ = Flightradar24Source.self }",
        )

        #expect(allowed.violations.isEmpty)
        #expect(rejected.violations.map(\.rule.id) == ["throw.provider_implementation_boundary"])
    }

    @Test func appLifecycleCallbacksCannotReplaceControllerSceneLifecycle() throws {
        let allowed = try evaluate(
            path: "Throw/Throw/Sources/ControllerSceneObserver.swift",
            component: .throwApp,
            source: "func controllerSceneDidEnterBackground() {}",
        )
        let rejected = try evaluate(
            path: "Throw/Throw/Sources/ThrowApp.swift",
            component: .throwApp,
            source: "func applicationDidEnterBackground() {}",
        )

        #expect(allowed.violations.isEmpty)
        #expect(rejected.violations.map(\.rule.id) == ["throw.controller_scene_lifecycle"])
    }

    @Test func uncheckedConcurrencyEscapeHatchesFail() throws {
        let preconcurrency = try evaluate(
            path: "Throw/ThrowCore/Sources/Legacy.swift",
            component: .throwCore,
            source: "@preconcurrency import Foundation",
        )
        let unsafeIsolation = try evaluate(
            path: "Throw/ThrowUI/Sources/UnsafeSession.swift",
            component: .throwUI,
            source: "final class Session { nonisolated(unsafe) var task: Task<Void, Never>? }",
        )

        #expect(
            preconcurrency.violations.map(\.rule.id) == ["throw.checked_concurrency_boundaries"],
        )
        #expect(
            unsafeIsolation.violations.map(\.rule.id) == ["throw.checked_concurrency_boundaries"],
        )
    }

    private func evaluate(
        path: RelativeFilePath,
        component: ThrowComponent,
        source: String,
    ) throws -> RuleReport {
        try RuleTestHarness(throwProjectRules).evaluate(
            VirtualRepository {
                VirtualSourceFile.swift(path, component: component, source: source)
            },
        )
    }
}
