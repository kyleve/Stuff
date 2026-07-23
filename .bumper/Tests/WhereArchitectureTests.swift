import BumperBowlingCore
import Testing

@Test
func `Where architecture accepts downward dependencies`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/WhereCore/Sources/Service.swift",
                    component: try ComponentID(WhereComponent.whereCore.rawValue),
                    source: "import RegionKit\nstruct Service {}"
                ),
                SourceInput(
                    path: "Where/WhereUI/Sources/Screen.swift",
                    component: try ComponentID(WhereComponent.whereUI.rawValue),
                    source: "import WhereCore\nimport SwiftUI\nstruct Screen {}"
                ),
            ]
        )
    )

    #expect(report.violations.isEmpty)
}

@Test
func `RegionKit cannot depend upward on WhereCore`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/RegionKit/Sources/Region.swift",
                    component: try ComponentID(WhereComponent.regionKit.rawValue),
                    source: "import WhereCore\nstruct Region {}"
                ),
            ]
        )
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .componentBoundary)
    #expect(violation.path.rawValue == "Where/RegionKit/Sources/Region.swift")
}

@Test
func `WhereUI cannot import persistence`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/WhereUI/Sources/Screen.swift",
                    component: try ComponentID(WhereComponent.whereUI.rawValue),
                    source: "import SwiftData\nstruct Screen {}"
                ),
            ]
        )
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .forbiddenImport)
    #expect(violation.path.rawValue == "Where/WhereUI/Sources/Screen.swift")
}
