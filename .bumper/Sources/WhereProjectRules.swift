import BumperBowlingCore
import SwiftSyntax

let whereProjectRules = RuleSet {
    Rules.constructionOwnership(
        "WhereServices",
        allowed: whereServicesConstructionScope,
        id: "where.services_composition_ownership"
    )
    Rules.constructionOwnership(
        "CoreLocationSource",
        allowed: .files(["Where/WhereUI/Sources/Launch/WhereLaunch.swift"]),
        id: "where.live_location_source_ownership"
    )
    Rules.singleNominalSpelling(
        suffix: "Log",
        owner: whereLoggingScope,
        id: "where.logging_type_ownership"
    )
    productionStoreOpeningRule
    checkedConcurrencyBoundaryRule
    gregorianCalendarRule
    storeTransactionBoundaryRule
    appShortcutsProviderOwnershipRule
    loggingFacadeRule
    previewCoverageRule
}

private let whereServicesConstructionScope = RuleScope
    .component(WhereComponent.whereCore)
    .union(.files(["Where/WhereUI/Sources/Preview/PreviewSupport.swift"]))

private let whereLoggingScope = RuleScope
    .under("Where/RegionKit/Sources/Logging")
    .union(.under("Where/WhereCore/Sources/Logging"))
    .union(.under("Where/WhereUI/Sources/Logging"))
    .union(.under("Where/WhereIntents/Sources/Logging"))
    .union(.under("Where/WhereWidgets/Sources/Logging"))
    .union(.under("Where/WhereShareExtension/Sources/Logging"))

private let productionStoreOpeningPaths: Set<RelativeFilePath> = [
    "Where/WhereUI/Sources/Launch/WhereLaunch.swift",
    "Where/WhereShareExtension/Sources/ShareEvidenceModel.swift",
]

private let productionStoreOpeningRule = Rules.files(
    "where.production_store_opening",
    severity: .error,
    summary: "Production SwiftData stores open only at the app and share-extension composition roots."
) { file in
    functionCalls()
        .filter { match in
            match.node.calledExpression.trimmedDescription == "SwiftDataStore.make"
                && !productionStoreOpeningPaths.contains(file.path)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "SwiftDataStore.make is called outside a process composition root.",
                evidence: ViolationEvidence(
                    observed: "SwiftDataStore.make in \(file.path.rawValue)",
                    expectation: "open the production store in WhereLaunch or ShareEvidenceModel"
                )
            )
        }
}

private let documentedUnsafeConcurrencyPaths: Set<RelativeFilePath> = [
    "Where/WhereCore/Sources/DataResolution/DataIssueScanner.swift",
    "Where/WhereCore/Sources/Persistence/SwiftDataStore.swift",
    "Where/WhereCore/Sources/RegionAttribution.swift",
    "Where/WhereUI/Sources/Model/WhereSession.swift",
    "Where/WhereUI/Sources/Model/YearReportModel.swift",
]

private let checkedConcurrencyBoundaryRule = Rules.files(
    "where.checked_concurrency_boundaries",
    severity: .error,
    summary: "Unchecked concurrency escape hatches stay inside documented lifecycle boundaries."
) { file in
    let preconcurrencyFailures = SyntaxQuery<AttributeSyntax>()
        .filter { match in
            match.node.attributeName.trimmedDescription == "preconcurrency"
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Production code uses an @preconcurrency escape hatch.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "use checked Swift concurrency"
                )
            )
        }

    let unsafeNonisolatedFailures = SyntaxQuery<DeclModifierSyntax>()
        .filter { match in
            match.node.name.text == "nonisolated"
                && match.node.tokens(viewMode: .sourceAccurate).contains { $0.text == "unsafe" }
                && !documentedUnsafeConcurrencyPaths.contains(file.path)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "nonisolated(unsafe) is outside a documented lifecycle boundary.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "checked isolation or a documented existing boundary"
                )
            )
        }

    return preconcurrencyFailures + unsafeNonisolatedFailures
}

private let gregorianCalendarRule = Rules.files(
    "where.gregorian_calendar",
    severity: .error,
    summary: "Where day and year calculations do not use the device's potentially non-Gregorian current calendar."
) { file in
    SyntaxQuery<MemberAccessExprSyntax>()
        .filter { match in
            match.node.base?.trimmedDescription == "Calendar"
                && match.node.declName.baseName.text == "current"
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Where uses Calendar.current instead of an explicit Gregorian calendar.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "an injected Gregorian calendar or Calendar.whereIntents"
                )
            )
        }
}

private let whereStoreMutatingMethods: Set<String> = [
    "add",
    "write",
    "setManualDay",
    "clearManualDay",
    "clear",
    "clearAll",
    "setIssueDismissed",
    "restoreDismissedIssue",
    "setTrackedRegion",
    "setPrimaryRegions",
]

private let storeTransactionBoundaryRule = Rules.files(
    "where.store_transaction_boundary",
    severity: .error,
    summary: "WhereStore mutations occur inside the transaction owned by store.perform."
) { file in
    functionCalls()
        .filter { match in
            guard
                let access = match.node.calledExpression.as(MemberAccessExprSyntax.self),
                ["store", "self.store"].contains(access.base?.trimmedDescription),
                whereStoreMutatingMethods.contains(access.declName.baseName.text)
            else {
                return false
            }
            return !isInsideStorePerform(match.node)
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "WhereStore mutation occurs outside store.perform.",
                evidence: ViolationEvidence(
                    observed: match.node.calledExpression.trimmedDescription,
                    expectation: "call the mutation from inside store.perform { ... }"
                )
            )
        }
}

private func isInsideStorePerform(_ node: FunctionCallExprSyntax) -> Bool {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if
            let call = current.as(FunctionCallExprSyntax.self),
            let access = call.calledExpression.as(MemberAccessExprSyntax.self),
            ["store", "self.store"].contains(access.base?.trimmedDescription),
            access.declName.baseName.text == "perform"
        {
            return true
        }
        ancestor = current.parent
    }
    return false
}

private let appShortcutsProviderOwnershipRule = Rules.files(
    "where.app_shortcuts_provider_ownership",
    severity: .error,
    summary: "AppShortcutsProvider conformances live in the Where app target."
) { file in
    guard file.component.rawValue != WhereComponent.app.rawValue else { return [] }
    return SyntaxQuery<InheritedTypeSyntax>()
        .filter { $0.node.type.trimmedDescription == "AppShortcutsProvider" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "AppShortcutsProvider conformance is outside the Where app target.",
                evidence: ViolationEvidence(
                    observed: file.path.rawValue,
                    expectation: "a source owned by the Where app component"
                )
            )
        }
}

private let loggingFacadeRule = Rules.files(
    "where.logging_facade",
    severity: .error,
    summary: "Where production logging goes through its typed Periscope facades."
) { file in
    let rawLoggingImports = SyntaxQuery<ImportDeclSyntax>()
        .filter { $0.node.path.trimmedDescription == "OSLog" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Where production code imports OSLog directly.",
                evidence: ViolationEvidence(
                    observed: "import OSLog",
                    expectation: "WhereLog or RegionLog"
                )
            )
        }

    let printCalls = functionCalls()
        .filter { $0.node.calledExpression.trimmedDescription == "print" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Where production code prints directly.",
                evidence: ViolationEvidence(
                    observed: "print",
                    expectation: "a typed WhereLog or RegionLog event"
                )
            )
        }

    return rawLoggingImports + printCalls
}

private let previewScope = RuleScope
    .component(WhereComponent.whereUI)
    .union(.component(WhereComponent.widgets))

private let previewCoverageRule = Rules.files(
    "where.preview_coverage",
    severity: .error,
    summary: "Every WhereUI or widget source file declaring a previewable component includes a #Preview.",
    scope: previewScope
) { file in
    let previewableDeclarations = SyntaxQuery<StructDeclSyntax>()
        .filter { match in
            let inheritedTypes = match.node.inheritanceClause?.inheritedTypes ?? []
            return inheritedTypes.contains { inherited in
                ["View", "Widget", "WidgetBundle"].contains(inherited.type.trimmedDescription)
            }
        }
        .matches(in: file)
    let hasPreviewDeclaration = !SyntaxQuery<MacroExpansionDeclSyntax>()
        .filter { match in match.node.macroName.text == "Preview" }
        .matches(in: file)
        .isEmpty
    let hasPreviewExpression = !SyntaxQuery<MacroExpansionExprSyntax>()
        .filter { match in match.node.macroName.text == "Preview" }
        .matches(in: file)
        .isEmpty
    let hasPreview = hasPreviewDeclaration || hasPreviewExpression

    guard !previewableDeclarations.isEmpty, !hasPreview else {
        return []
    }

    return previewableDeclarations.map { match in
        match.failure(
            message: "\(match.node.name.text) has no #Preview in its source file.",
            evidence: ViolationEvidence(
                observed: file.path.rawValue,
                expectation: "at least one #Preview in the same file"
            )
        )
    }
}
