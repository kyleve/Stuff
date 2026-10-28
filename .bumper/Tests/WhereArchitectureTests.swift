import BumperBowlingCore
import Testing

@Test(arguments: ["Where/RegionKit/Sources", "Where/RegionKit/Sources/Nested"])
func `Where architecture rejects overlapping ownership`(duplicatePath: String) throws {
    let allowed = try bumper.evaluate(RepositoryInput(architecture: bumper.architecture, files: []))
    #expect(allowed.violations.isEmpty)

    let architecture = try WhereArchitectureTestSupport.replacing(.whereCore) { component in
        ComponentConfiguration(
            name: component.name,
            modules: component.modules,
            paths: component.paths + [duplicatePath],
            mayDependOn: component.mayDependOn,
            mustNotDependOn: component.mustNotDependOn,
        )
    }
    let rejected = try bumper.evaluate(RepositoryInput(architecture: architecture, files: []))

    let violation = try #require(rejected.violations.first)
    #expect(rejected.violations.count == 1)
    #expect(violation.rule.id == .duplicateOwnership)
    #expect(violation.rule.severity == .error)
    #expect(violation.path.rawValue == duplicatePath)
}

@Test
func `Where architecture rejects a declared dependency cycle`() throws {
    let allowed = try bumper.evaluate(RepositoryInput(architecture: bumper.architecture, files: []))
    #expect(allowed.violations.isEmpty)

    let dependency = try ComponentID(WhereComponent.whereCore.rawValue)
    let architecture = try WhereArchitectureTestSupport.replacing(.regionKit) { component in
        ComponentConfiguration(
            name: component.name,
            modules: component.modules,
            paths: component.paths,
            mayDependOn: component.mayDependOn + [dependency.rawValue],
            mustNotDependOn: component.mustNotDependOn,
        )
    }
    let rejected = try bumper.evaluate(RepositoryInput(architecture: architecture, files: []))

    let violation = try #require(rejected.violations.first)
    #expect(rejected.violations.count == 1)
    #expect(violation.rule.id == .declaredDependencyCycle)
    #expect(violation.rule.severity == .error)
}

@Test
func `Where architecture rejects duplicate module ownership`() throws {
    let architecture = try WhereArchitectureTestSupport.replacing(.whereCore) { component in
        ComponentConfiguration(
            name: component.name,
            modules: component.modules + ["RegionKit"],
            paths: component.paths,
            mayDependOn: component.mayDependOn,
            mustNotDependOn: component.mustNotDependOn,
        )
    }

    #expect(throws: ConfigurationError.duplicateModule("RegionKit")) {
        try ArchitectureRules(configuration: architecture)
    }
}

@Test
func `Where architecture accepts downward dependencies`() throws {
    let report = try bumper.evaluate(
        RepositoryInput(
            architecture: bumper.architecture,
            files: [
                SourceInput(
                    path: "Where/WhereCore/Sources/Service.swift",
                    component: ComponentID(WhereComponent.whereCore.rawValue),
                    source: "import RegionKit\nimport StorageKit\nstruct Service {}",
                ),
                SourceInput(
                    path: "Where/WhereUI/Sources/Screen.swift",
                    component: ComponentID(WhereComponent.whereUI.rawValue),
                    source: "import WhereCore\nimport SwiftUI\nstruct Screen {}",
                ),
            ],
        ),
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

@Test
func `InstallerKit rejects app and UI dependencies`() throws {
    for source in [
        "import WhereCore",
        "import WhereUI",
        "import InstallerKitUI",
        "import UIKit",
        "import SwiftUI",
    ] {
        let report = try bumper.evaluate(RepositoryInput(
            architecture: bumper.architecture,
            files: [SourceInput(
                path: "Shared/InstallerKit/Sources/UpdateService.swift",
                component: ComponentID(WhereComponent.installerKit.rawValue),
                source: source,
            )],
        ))
        #expect(!report.violations.isEmpty)
    }
}

@Test
func `InstallerKitUI can use the engine but rejects host dependencies`() throws {
    for source in ["import InstallerKit\nimport SwiftUI", "import WhereCore", "import WhereUI"] {
        let report = try bumper.evaluate(RepositoryInput(
            architecture: bumper.architecture,
            files: [SourceInput(
                path: "Shared/InstallerKitUI/Sources/AppUpdatesView.swift",
                component: ComponentID(WhereComponent.installerKitUI.rawValue),
                source: source,
            )],
        ))
        #expect(report.violations.isEmpty == source.hasPrefix("import InstallerKit\n"))
    }
}

@Test
func `Where consumers can use InstallerKit`() throws {
    let report = try bumper.evaluate(RepositoryInput(
        architecture: bumper.architecture,
        files: [SourceInput(
            path: "Where/WhereCore/Sources/About/BuildInfo.swift",
            component: ComponentID(WhereComponent.whereCore.rawValue),
            source: "import InstallerKit",
        )],
    ))
    #expect(report.violations.isEmpty)
}

@Test
func `StorageKit rejects app and UI dependencies`() throws {
    let path: RelativeFilePath = "Shared/StorageKit/Sources/Storage.swift"
    let allowed = try bumper.evaluate(RepositoryInput(
        architecture: bumper.architecture,
        files: [SourceInput(
            path: path,
            component: ComponentID(WhereComponent.storageKit.rawValue),
            source: "import Foundation\nimport SwiftData",
        )],
    ))
    #expect(allowed.violations.isEmpty)
    for source in ["import WhereCore", "import WhereUI", "import UIKit", "import SwiftUI"] {
        let report = try bumper.evaluate(RepositoryInput(
            architecture: bumper.architecture,
            files: [SourceInput(
                path: path,
                component: ComponentID(WhereComponent.storageKit.rawValue),
                source: source,
            )],
        ))
        let violation = try #require(report.violations.first)
        #expect(report.violations.count == 1)
        #expect(violation.path == path)
        #expect(violation.rule.severity == .error)
        #expect(violation.rule
            .id == (source.contains("Where") ? .componentBoundary : .forbiddenImport))
    }
}
