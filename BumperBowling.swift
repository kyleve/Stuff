import BumperBowlingCore

enum WhereComponent: String, ComponentKey {
    case periscope
    case ledgerCore
    case loggingTests
    case installerKit
    case installerKitUI
    case regionKit
    case whereCore
    case whereUI
    case whereIntents
    case app
    case widgets
    case shareExtension
    case regionViewer
}

let bumper = BumperProject {
    Included {
        "Shared/Periscope/PeriscopeCore/Sources"
        "Shared/Periscope/PeriscopeMacros/Sources"
        "Shared/Periscope/PeriscopeTools/Sources"
        "Shared/Periscope/PeriscopeUI/Sources"
        "Shared/Periscope/PeriscopeCore/Tests"
        "Shared/Periscope/PeriscopeMacros/Tests"
        "Shared/Periscope/PeriscopeTools/Tests"
        "Shared/Periscope/PeriscopeUI/Tests"
        "Shared/InstallerKit/Sources"
        "Shared/InstallerKit/Tests"
        "Shared/InstallerKitUI/Sources"
        "Shared/InstallerKitUI/Tests"
        "Ledger/LedgerCore/Sources"
        "Ledger/LedgerCore/Tests"
        "Where/RegionKit/Sources"
        "Where/RegionKit/Tests"
        "Where/WhereCore/Sources"
        "Where/WhereCore/Tests"
        "Where/WhereUI/Sources"
        "Where/WhereUI/Tests"
        "Where/WhereIntents/Sources"
        "Where/WhereIntents/Tests"
        "Where/Where/Sources"
        "Where/Where/Tests"
        "Where/WhereWidgets/Sources"
        "Where/WhereShareExtension/Sources"
        "Where/RegionViewer/Sources"
    }

    Excluded {
        ".build"
        "Derived"
        "DerivedData"
    }

    Architecture(WhereComponent.self) {
        Component(.periscope) {
            Owns("Shared/Periscope/PeriscopeCore/Sources")
            Owns("Shared/Periscope/PeriscopeMacros/Sources")
            Owns("Shared/Periscope/PeriscopeTools/Sources")
            Owns("Shared/Periscope/PeriscopeUI/Sources")
            Modules("PeriscopeCore", "PeriscopeMacros", "PeriscopeTools", "PeriscopeUI")
        }

        Component(.installerKit) {
            Owns("Shared/InstallerKit/Sources")
            Modules("InstallerKit")
            MayDependOn(.periscope)
            Applies(.whereFoundationLayer)
        }

        Component(.installerKitUI) {
            Owns("Shared/InstallerKitUI/Sources")
            Modules("InstallerKitUI")
            MayDependOn(.installerKit)
            Applies(.wherePresentationLayer)
        }

        Component(.ledgerCore) {
            Owns("Ledger/LedgerCore/Sources")
            Modules("LedgerCore")
            MayDependOn(.periscope)
        }

        Component(.loggingTests) {
            Owns("Shared/Periscope/PeriscopeCore/Tests")
            Owns("Shared/Periscope/PeriscopeMacros/Tests")
            Owns("Shared/Periscope/PeriscopeTools/Tests")
            Owns("Shared/Periscope/PeriscopeUI/Tests")
            Owns("Shared/InstallerKit/Tests")
            Owns("Shared/InstallerKitUI/Tests")
            Owns("Ledger/LedgerCore/Tests")
            Owns("Where/RegionKit/Tests")
            Owns("Where/WhereCore/Tests")
            Owns("Where/WhereUI/Tests")
            Owns("Where/WhereIntents/Tests")
            Owns("Where/Where/Tests")
            MayDependOn(
                .periscope,
                .ledgerCore,
                .installerKit,
                .installerKitUI,
                .regionKit,
                .whereCore,
                .whereUI,
                .whereIntents,
                .app,
                .widgets,
                .shareExtension,
                .regionViewer,
            )
        }

        Component(.regionKit) {
            Owns("Where/RegionKit/Sources")
            Modules("RegionKit")
            MayDependOn(.periscope)
            Applies(.whereFoundationLayer)
            DoesNotUse("CoreLocation")
        }

        Component(.whereCore) {
            Owns("Where/WhereCore/Sources")
            Modules("WhereCore")
            MayDependOn(.periscope, .installerKit, .regionKit)
            Applies(.whereDomainLayer)
        }

        Component(.whereUI) {
            Owns("Where/WhereUI/Sources")
            Modules("WhereUI")
            MayDependOn(.periscope, .installerKit, .installerKitUI, .regionKit, .whereCore)
            Applies(.wherePresentationLayer)
        }

        Component(.whereIntents) {
            Owns("Where/WhereIntents/Sources")
            Modules("WhereIntents")
            MayDependOn(.periscope, .regionKit, .whereCore, .whereUI)
            Applies(.whereAdapterLayer)
            DoesNotUse("CoreLocation")
            DoesNotUse("BroadwayCore", "BroadwayUI")
        }

        Component(.app) {
            Owns("Where/Where/Sources")
            Modules("Where")
            MayDependOn(.periscope, .installerKit, .regionKit, .whereCore, .whereUI, .whereIntents)
            Applies(.whereHostLayer)
        }

        Component(.widgets) {
            Owns("Where/WhereWidgets/Sources")
            Modules("WhereWidgets")
            MayDependOn(.periscope, .regionKit, .whereCore, .whereUI)
            Applies(.whereAdapterLayer)
            DoesNotUse("BroadwayCore", "BroadwayUI")
        }

        Component(.shareExtension) {
            Owns("Where/WhereShareExtension/Sources")
            Modules("WhereShareExtension")
            MayDependOn(.periscope, .whereCore, .whereUI)
            Applies(.whereAdapterLayer)
        }

        Component(.regionViewer) {
            Owns("Where/RegionViewer/Sources")
            Modules("RegionViewer")
            MayDependOn(.periscope, .regionKit, .whereCore, .whereUI)
            Applies(.whereHostLayer)
        }
    }

    Rules {
        ApplyAssertions(.whereArchitecture)
        whereProjectRules
        periscopeAuthoringRules
    }
}
