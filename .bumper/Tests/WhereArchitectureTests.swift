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
                    component: ComponentID(WhereComponent.whereCore.rawValue),
                    source: "import RegionKit\nimport WhereSurface\nstruct Service {}",
                ),
                SourceInput(
                    path: "Where/WhereUI/Sources/Screen.swift",
                    component: ComponentID(WhereComponent.whereUI.rawValue),
                    source: "import WhereCore\nimport SwiftUI\nstruct Screen {}",
                ),
                SourceInput(
                    path: "Where/WhereMenuBar/Sources/MenuBar.swift",
                    component: ComponentID(WhereComponent.menuBar.rawValue),
                    source: "import SwiftUI\nimport WhereSurface\nstruct MenuBar {}",
                ),
            ],
        ),
    )

    #expect(report.violations.isEmpty)
}

@Test
func `WhereSurface cannot depend upward on WhereCore`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/WhereSurface/Sources/Snapshot.swift",
                    component: ComponentID(WhereComponent.whereSurface.rawValue),
                    source: "import WhereCore\nstruct Snapshot {}",
                ),
            ],
        ),
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .componentBoundary)
    #expect(violation.path.rawValue == "Where/WhereSurface/Sources/Snapshot.swift")
}

@Test
func `RegionKit cannot depend upward on WhereCore`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/RegionKit/Sources/Region.swift",
                    component: ComponentID(WhereComponent.regionKit.rawValue),
                    source: "import WhereCore\nstruct Region {}",
                ),
            ],
        ),
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
                    component: ComponentID(WhereComponent.whereUI.rawValue),
                    source: "import SwiftData\nstruct Screen {}",
                ),
            ],
        ),
    )

    let violation = try #require(report.violations.first)
    #expect(report.violations.count == 1)
    #expect(violation.rule.id == .forbiddenImport)
    #expect(violation.path.rawValue == "Where/WhereUI/Sources/Screen.swift")
}

@Test
func `Where adapters cannot link Broadway directly`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/WhereWidgets/Sources/Widget.swift",
                    component: ComponentID(WhereComponent.widgets.rawValue),
                    source: "import BroadwayUI\nstruct Widget {}",
                ),
                SourceInput(
                    path: "Where/WhereIntents/Sources/Intent.swift",
                    component: ComponentID(WhereComponent.whereIntents.rawValue),
                    source: "import BroadwayCore\nstruct Intent {}",
                ),
            ],
        ),
    )

    #expect(report.violations.count == 2)
    #expect(report.violations.allSatisfy { $0.rule.id == .forbiddenImport })
}
