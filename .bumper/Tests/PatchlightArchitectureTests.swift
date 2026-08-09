import BumperBowlingCore
import Testing

@Test
func `Patchlight accepts Core to UI to host dependencies`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Patchlight/PatchlightCore/Sources/Review.swift",
                    component: ComponentID(PatchlightComponent.core.rawValue),
                    source: "import Foundation\nstruct Review {}",
                ),
                SourceInput(
                    path: "Patchlight/PatchlightUI/Sources/Screen.swift",
                    component: ComponentID(PatchlightComponent.ui.rawValue),
                    source: "import PatchlightCore\nimport SwiftUI\nstruct Screen {}",
                ),
                SourceInput(
                    path: "Patchlight/Patchlight/Sources/App.swift",
                    component: ComponentID(PatchlightComponent.host.rawValue),
                    source: "import PatchlightUI\nimport SwiftUI\nstruct App {}",
                ),
            ],
        ),
    )

    #expect(report.violations.isEmpty)
}

@Test
func `PatchlightCore cannot import UI`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Patchlight/PatchlightCore/Sources/Upward.swift",
                    component: ComponentID(PatchlightComponent.core.rawValue),
                    source: "import PatchlightUI\nstruct Upward {}",
                ),
            ],
        ),
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .componentBoundary)
}

@Test
func `PatchlightCore cannot import UI frameworks`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Patchlight/PatchlightCore/Sources/Leaky.swift",
                    component: ComponentID(PatchlightComponent.core.rawValue),
                    source: "import SwiftUI\nimport UIKit\nstruct Leaky {}",
                ),
            ],
        ),
    )

    #expect(report.violations.count == 2)
    #expect(report.violations.allSatisfy { $0.rule.id == .forbiddenImport })
}

@Test
func `Patchlight host cannot bypass UI for Core`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Patchlight/Patchlight/Sources/Bypass.swift",
                    component: ComponentID(PatchlightComponent.host.rawValue),
                    source: "import PatchlightCore\nstruct Bypass {}",
                ),
            ],
        ),
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .componentBoundary)
}
