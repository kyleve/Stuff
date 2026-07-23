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
    intentCalendarRule
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

private let intentCalendarRule = Rules.files(
    "where.intents_calendar",
    severity: .error,
    summary: "Where intents use the Gregorian current-time-zone calendar shared with aggregation.",
    scope: .component(WhereComponent.whereIntents)
) { file in
    SyntaxQuery<MemberAccessExprSyntax>()
        .filter { match in
            match.node.base?.trimmedDescription == "Calendar"
                && match.node.declName.baseName.text == "current"
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "WhereIntents uses Calendar.current instead of Calendar.whereIntents.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "Calendar.whereIntents"
                )
            )
        }
}
