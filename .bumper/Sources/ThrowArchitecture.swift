import BumperBowlingCore

extension ComponentShape {
    static let throwCoreLayer = ComponentShape {
        MayUse(.foundation)
    }

    static let throwPresentationLayer = ComponentShape {
        MayUse(.foundation, .swiftUI, .uiKit)
    }

    static let throwHostLayer = ComponentShape {
        MayUse(.foundation, .swiftUI, .uiKit)
    }
}

extension AssertionShape {
    static let throwArchitecture = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}
