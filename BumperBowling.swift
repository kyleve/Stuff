import BumperBowlingCore

enum WhereComponent: String, ComponentKey {
    case regionKit
    case whereCore
    case whereUI
    case whereIntents
    case app
    case widgets
    case shareExtension
    case regionViewer
}

enum ThrowComponent: String, ComponentKey {
    case throwCore
    case throwUI
    case throwApp
}

let bumper = BumperProject {
    Included {
        "Where/RegionKit/Sources"
        "Where/WhereCore/Sources"
        "Where/WhereUI/Sources"
        "Where/WhereIntents/Sources"
        "Where/Where/Sources"
        "Where/WhereWidgets/Sources"
        "Where/WhereShareExtension/Sources"
        "Where/RegionViewer/Sources"
        "Throw/ThrowCore/Sources"
        "Throw/ThrowUI/Sources"
        "Throw/Throw/Sources"
    }

    Excluded {
        ".build"
        "Derived"
        "DerivedData"
    }

    Architecture(WhereComponent.self) {
        Component(.regionKit) {
            Owns("Where/RegionKit/Sources")
            Modules("RegionKit")
            Applies(.whereFoundationLayer)
            DoesNotUse("CoreLocation")
        }

        Component(.whereCore) {
            Owns("Where/WhereCore/Sources")
            Modules("WhereCore")
            MayDependOn(.regionKit)
            Applies(.whereDomainLayer)
        }

        Component(.whereUI) {
            Owns("Where/WhereUI/Sources")
            Modules("WhereUI")
            MayDependOn(.regionKit, .whereCore)
            Applies(.wherePresentationLayer)
        }

        Component(.whereIntents) {
            Owns("Where/WhereIntents/Sources")
            Modules("WhereIntents")
            MayDependOn(.regionKit, .whereCore, .whereUI)
            Applies(.whereAdapterLayer)
            DoesNotUse("CoreLocation")
            DoesNotUse("BroadwayCore", "BroadwayUI")
        }

        Component(.app) {
            Owns("Where/Where/Sources")
            Modules("Where")
            MayDependOn(.regionKit, .whereCore, .whereUI, .whereIntents)
            Applies(.whereHostLayer)
        }

        Component(.widgets) {
            Owns("Where/WhereWidgets/Sources")
            Modules("WhereWidgets")
            MayDependOn(.regionKit, .whereCore, .whereUI)
            Applies(.whereAdapterLayer)
            DoesNotUse("BroadwayCore", "BroadwayUI")
        }

        Component(.shareExtension) {
            Owns("Where/WhereShareExtension/Sources")
            Modules("WhereShareExtension")
            MayDependOn(.whereCore, .whereUI)
            Applies(.whereAdapterLayer)
        }

        Component(.regionViewer) {
            Owns("Where/RegionViewer/Sources")
            Modules("RegionViewer")
            MayDependOn(.regionKit, .whereCore, .whereUI)
            Applies(.whereHostLayer)
        }
    }

    Architecture(ThrowComponent.self) {
        Component(.throwCore) {
            Owns("Throw/ThrowCore/Sources")
            Modules("ThrowCore")
            Applies(.throwCoreLayer)
            DoesNotUse("LifecycleKit")
        }

        Component(.throwUI) {
            Owns("Throw/ThrowUI/Sources")
            Modules("ThrowUI")
            MayDependOn(.throwCore)
            Applies(.throwPresentationLayer)
            DoesNotUse("LifecycleKit")
        }

        Component(.throwApp) {
            Owns("Throw/Throw/Sources")
            Modules("Throw")
            MayDependOn(.throwUI)
            Applies(.throwHostLayer)
        }
    }

    Rules {
        ApplyAssertions(.whereArchitecture)
        ApplyAssertions(.throwArchitecture)
        repositoryProjectRules
        whereProjectRules
        throwProjectRules
    }
}
