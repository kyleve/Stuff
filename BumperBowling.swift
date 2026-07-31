import BumperBowlingCore

enum WhereComponent: String, ComponentKey {
    case regionKit
    case whereSurface
    case whereCore
    case whereUI
    case whereIntents
    case app
    case widgets
    case shareExtension
    case menuBar
    case regionViewer
}

let bumper = BumperProject {
    Included {
        "Where/RegionKit/Sources"
        "Where/WhereSurface/Sources"
        "Where/WhereCore/Sources"
        "Where/WhereUI/Sources"
        "Where/WhereIntents/Sources"
        "Where/Where/Sources"
        "Where/WhereWidgets/Sources"
        "Where/WhereShareExtension/Sources"
        "Where/WhereMenuBar/Sources"
        "Where/RegionViewer/Sources"
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

        Component(.whereSurface) {
            Owns("Where/WhereSurface/Sources")
            Modules("WhereSurface")
            Applies(.whereFoundationLayer)
        }

        Component(.whereCore) {
            Owns("Where/WhereCore/Sources")
            Modules("WhereCore")
            MayDependOn(.regionKit, .whereSurface)
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

        Component(.menuBar) {
            Owns("Where/WhereMenuBar/Sources")
            Modules("WhereMenuBar")
            MayDependOn(.whereSurface)
            Applies(.whereMacHostLayer)
            DoesNotUse("CoreLocation", "SwiftData")
        }

        Component(.regionViewer) {
            Owns("Where/RegionViewer/Sources")
            Modules("RegionViewer")
            MayDependOn(.regionKit, .whereCore, .whereUI)
            Applies(.whereHostLayer)
        }
    }

    Rules {
        ApplyAssertions(.whereArchitecture)
        whereProjectRules
    }
}
