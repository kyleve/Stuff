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
}

extension AssertionShape {
    static let whereArchitecture = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
