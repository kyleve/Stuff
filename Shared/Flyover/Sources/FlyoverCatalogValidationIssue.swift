/// A structural problem in a Flyover catalog.
public enum FlyoverCatalogValidationIssue<ScreenID: Hashable>: Equatable {
    case duplicateGroupID(FlyoverGroupID)
    case duplicateScreenID(ScreenID)
    case duplicateVariantID(screen: ScreenID, variant: FlyoverVariantID)
    case duplicateControlID(screen: ScreenID, control: AnyHashable)
    case missingGroupRoot(group: FlyoverGroupID, root: ScreenID)
    case danglingTransitionEndpoint(ScreenID)
    case duplicateTransition(
        source: ScreenID,
        destination: ScreenID,
        kind: FlyoverTransition<ScreenID>.Kind,
    )
    case conflictingPosition(
        group: FlyoverGroupID,
        position: FlyoverPosition,
        first: ScreenID,
        second: ScreenID,
    )
}
