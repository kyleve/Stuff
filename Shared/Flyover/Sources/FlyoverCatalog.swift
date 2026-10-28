/// The complete typed registry rendered by ``FlyoverView``.
@MainActor
public struct FlyoverCatalog<ScreenID: Hashable> {
    public let groups: [FlyoverGroup<ScreenID>]
    public let transitions: [FlyoverTransition<ScreenID>]
    public let validationIssues: [FlyoverCatalogValidationIssue<ScreenID>]

    public init(
        groups: [FlyoverGroup<ScreenID>],
        transitions: [FlyoverTransition<ScreenID>] = [],
    ) {
        precondition(groups.isEmpty == false, "A Flyover catalog must contain a group.")
        self.groups = groups
        self.transitions = transitions
        validationIssues = Self.validate(groups: groups, transitions: transitions)
    }

    public var screens: [FlyoverScreen<ScreenID>] {
        groups.flatMap(\.screens)
    }

    public var isValid: Bool {
        validationIssues.isEmpty
    }

    func screen(id: ScreenID) -> FlyoverScreen<ScreenID>? {
        screens.first { $0.id == id }
    }

    private static func validate(
        groups: [FlyoverGroup<ScreenID>],
        transitions: [FlyoverTransition<ScreenID>],
    ) -> [FlyoverCatalogValidationIssue<ScreenID>] {
        var issues: [FlyoverCatalogValidationIssue<ScreenID>] = []
        var seenGroupIDs: Set<FlyoverGroupID> = []
        var seenScreenIDs: Set<ScreenID> = []

        for group in groups {
            if seenGroupIDs.insert(group.id).inserted == false {
                issues.append(.duplicateGroupID(group.id))
            }

            var positions: [FlyoverPosition: ScreenID] = [:]
            for screen in group.screens {
                if seenScreenIDs.insert(screen.id).inserted == false {
                    issues.append(.duplicateScreenID(screen.id))
                }

                var seenVariantIDs: Set<FlyoverVariantID> = []
                for variant in screen.variants {
                    if seenVariantIDs.insert(variant.id).inserted == false {
                        issues.append(
                            .duplicateVariantID(screen: screen.id, variant: variant.id),
                        )
                    }
                }

                var seenControlIDs: Set<AnyHashable> = []
                for control in screen.controls {
                    if seenControlIDs.insert(control.id).inserted == false {
                        issues.append(
                            .duplicateControlID(screen: screen.id, control: control.id),
                        )
                    }
                }

                if let position = screen.position {
                    if let existing = positions[position] {
                        issues.append(
                            .conflictingPosition(
                                group: group.id,
                                position: position,
                                first: existing,
                                second: screen.id,
                            ),
                        )
                    } else {
                        positions[position] = screen.id
                    }
                }
            }
            if group.screens.contains(where: { $0.id == group.root }) == false {
                issues.append(.missingGroupRoot(group: group.id, root: group.root))
            }
        }

        var seenTransitions: Set<TransitionKey> = []
        for transition in transitions {
            if seenScreenIDs.contains(transition.source) == false {
                issues.append(.danglingTransitionEndpoint(transition.source))
            }
            if seenScreenIDs.contains(transition.destination) == false {
                issues.append(.danglingTransitionEndpoint(transition.destination))
            }
            let key = TransitionKey(transition)
            if seenTransitions.insert(key).inserted == false {
                issues.append(
                    .duplicateTransition(
                        source: transition.source,
                        destination: transition.destination,
                        kind: transition.kind,
                    ),
                )
            }
        }
        return issues
    }

    private struct TransitionKey: Hashable {
        let source: ScreenID
        let destination: ScreenID
        let kind: FlyoverTransition<ScreenID>.Kind

        init(_ transition: FlyoverTransition<ScreenID>) {
            source = transition.source
            destination = transition.destination
            kind = transition.kind
        }
    }
}
