import BumperBowlingCore

extension ComponentShape {
    static let whereFoundationLayer = ComponentShape {
        MayUse(.foundation)
    }

    static let whereDomainLayer = ComponentShape {
        MayUse(.foundation, .persistence)
    }

    static let wherePresentationLayer = ComponentShape {
        MayUse(.foundation, .swiftUI, .uiKit)
    }

    static let whereAdapterLayer = ComponentShape {
        MayUse(.foundation, .swiftUI, .uiKit)
    }

    static let whereHostLayer = ComponentShape {
        MayUse(.foundation, .swiftUI, .uiKit)
    }

    static let whereMacHostLayer = ComponentShape {
        // Bumper Bowling has no AppKit capability yet; AppKit is the native
        // host framework and the component's explicit dependency rules still
        // forbid CoreLocation and SwiftData.
        MayUse(.foundation, .swiftUI)
    }
}

extension AssertionShape {
    static let whereArchitecture = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
