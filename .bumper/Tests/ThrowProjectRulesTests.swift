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
        #expect(rejected.violations.count == 6)
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
