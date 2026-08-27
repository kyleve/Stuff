import BumperBowlingCore
import Testing

struct ThrowArchitectureTests {
    @Test func downwardDependenciesPass() throws {
        let report = try bumper.evaluate(
            RepositoryInput(
                architecture: bumper.architecture,
                files: [
                    SourceInput(
                        path: "Throw/ThrowUI/Sources/Screen.swift",
                        component: ComponentID(ThrowComponent.throwUI.rawValue),
                        source: "import ThrowCore\nimport SwiftUI\nstruct Screen {}",
                    ),
                    SourceInput(
                        path: "Throw/Throw/Sources/App.swift",
                        component: ComponentID(ThrowComponent.throwApp.rawValue),
                        source: "import ThrowUI\nimport UIKit\nstruct AppHost {}",
                    ),
                ],
            ),
        )

        #expect(report.violations.isEmpty)
    }

    @Test func coreCannotImportUIFrameworks() throws {
        let report = try bumper.evaluate(
            RepositoryInput(
                architecture: bumper.architecture,
                files: [SourceInput(
                    path: "Throw/ThrowCore/Sources/LeakingDomain.swift",
                    component: ComponentID(ThrowComponent.throwCore.rawValue),
                    source: "import SwiftUI\nstruct LeakingDomain {}",
                )],
            ),
        )

        #expect(report.violations.map(\.rule.id) == [.forbiddenImport])
    }

    @Test func uiCannotImportWhereModules() throws {
        let report = try bumper.evaluate(
            RepositoryInput(
                architecture: bumper.architecture,
                files: [SourceInput(
                    path: "Throw/ThrowUI/Sources/LeakingScreen.swift",
                    component: ComponentID(ThrowComponent.throwUI.rawValue),
                    source: "import WhereCore\nstruct LeakingScreen {}",
                )],
            ),
        )

        #expect(report.violations.map(\.rule.id) == [.componentBoundary])
    }

    @Test func appCannotBypassUIToImportCore() throws {
        let report = try bumper.evaluate(
            RepositoryInput(
                architecture: bumper.architecture,
                files: [SourceInput(
                    path: "Throw/Throw/Sources/LeakingApp.swift",
                    component: ComponentID(ThrowComponent.throwApp.rawValue),
                    source: "import ThrowCore\nstruct LeakingApp {}",
                )],
            ),
        )

        #expect(report.violations.map(\.rule.id) == [.componentBoundary])
    }
}
