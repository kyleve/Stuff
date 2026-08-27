import BumperBowlingCore
import SwiftSyntax

let throwProjectRules = RuleSet {
    throwAnyViewRule
    throwProviderBoundaryRule
    throwCheckedConcurrencyRule
}

private let throwProductionScope = RuleScope
    .component(ThrowComponent.throwCore)
    .union(.component(ThrowComponent.throwUI))
    .union(.component(ThrowComponent.throwApp))

private let throwAnyViewRule = Rules.files(
    "throw.no_any_view",
    severity: .error,
    summary: "Throw production boundaries preserve concrete SwiftUI view types.",
    scope: throwProductionScope,
) { file in
    let typeFailures = SyntaxQuery<IdentifierTypeSyntax>()
        .filter { $0.node.name.text == "AnyView" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code erases a SwiftUI view to AnyView.",
                evidence: ViolationEvidence(
                    observed: "AnyView in \(file.path.rawValue)",
                    expectation: "a concrete view or a generic view boundary",
                ),
            )
        }
    let constructionFailures = functionCalls()
        .filter { $0.node.calledExpression.trimmedDescription == "AnyView" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code constructs an AnyView.",
                evidence: ViolationEvidence(
                    observed: "AnyView in \(file.path.rawValue)",
                    expectation: "a concrete view or a generic view boundary",
                ),
            )
        }
    return typeFailures + constructionFailures
}

private let providerImplementationNames: Set<String> = [
    "ADSBExchangeRapidAPISource",
    "ADSBExchangeV2Decoder",
    "AdsBLolSource",
    "Flightradar24Decoder",
    "Flightradar24Source",
    "ReadsbSource",
]

private let throwProviderBoundaryRule = Rules.files(
    "throw.provider_implementation_boundary",
    severity: .error,
    summary: "ThrowUI uses provider-neutral source operations instead of concrete adapters.",
    scope: .component(ThrowComponent.throwUI),
) { file in
    let typeFailures = SyntaxQuery<IdentifierTypeSyntax>()
        .filter { providerImplementationNames.contains($0.node.name.text) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "ThrowUI refers to a concrete aircraft provider implementation.",
                evidence: ViolationEvidence(
                    observed: match.node.name.text,
                    expectation: "an injected provider-neutral ThrowCore operation",
                ),
            )
        }
    let referenceFailures = SyntaxQuery<DeclReferenceExprSyntax>()
        .filter { providerImplementationNames.contains($0.node.baseName.text) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "ThrowUI refers to a concrete aircraft provider implementation.",
                evidence: ViolationEvidence(
                    observed: match.node.baseName.text,
                    expectation: "an injected provider-neutral ThrowCore operation",
                ),
            )
        }
    return typeFailures + referenceFailures
}

private let throwCheckedConcurrencyRule = Rules.files(
    "throw.checked_concurrency_boundaries",
    severity: .error,
    summary: "Throw production code uses checked Swift concurrency.",
    scope: throwProductionScope,
) { file in
    let preconcurrencyFailures = SyntaxQuery<AttributeSyntax>()
        .filter { $0.node.attributeName.trimmedDescription == "preconcurrency" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code uses an @preconcurrency escape hatch.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "checked Swift concurrency",
                ),
            )
        }
    let unsafeNonisolatedFailures = SyntaxQuery<DeclModifierSyntax>()
        .filter { match in
            match.node.name.text == "nonisolated"
                && match.node.tokens(viewMode: .sourceAccurate).contains { $0.text == "unsafe" }
        }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code uses nonisolated(unsafe).",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "checked actor isolation",
                ),
            )
        }
    return preconcurrencyFailures + unsafeNonisolatedFailures
}
