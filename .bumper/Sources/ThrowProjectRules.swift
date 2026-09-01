import BumperBowlingCore
import SwiftSyntax

let throwProjectRules = RuleSet {
    Rules.constructionOwnership(
        "ThrowSession",
        allowed: .files([throwSessionCompositionPath]),
        id: "throw.session_composition_ownership",
    )
    Rules.constructionOwnership(
        "ThrowRuntime",
        allowed: .files([throwRuntimeCompositionPath]),
        id: "throw.runtime_composition_ownership",
    )
    Rules.constructionOwnership(
        "LayerFrame",
        allowed: .files([throwLayerFrameErasurePath]),
        id: "throw.layer_frame_erasure_ownership",
    )
    throwLiveDependencyCompositionRule
    throwAnyViewRule
    throwProviderBoundaryRule
    throwSceneLifecycleRule
    throwCheckedConcurrencyRule
    throwLoggingFacadeRule
}

private let throwSessionCompositionPath: RelativeFilePath =
    "Throw/ThrowUI/Sources/Model/ThrowSession+Composition.swift"
private let throwRuntimeCompositionPath: RelativeFilePath =
    "Throw/Throw/Sources/ThrowRuntime.swift"
private let throwLayerFrameErasurePath: RelativeFilePath =
    "Throw/ThrowCore/Sources/ProjectionModels.swift"

private let throwProductionScope = RuleScope
    .component(ThrowComponent.throwCore)
    .union(.component(ThrowComponent.throwUI))
    .union(.component(ThrowComponent.throwApp))

private let throwLiveDependencyNames: Set<String> = [
    "AircraftPollingCoordinator",
    "AircraftSourceFactory",
    "AircraftSourceService",
    "CoreLocationThrowSource",
    "KeychainAircraftCredentialStore",
    "PeriscopeThrowDurableLoggingStarter",
    "UserDefaultsThrowPreferenceStore",
]

private let throwLiveDependencyCompositionRule = Rules.files(
    "throw.live_dependency_composition_ownership",
    severity: .error,
    summary: "Throw constructs live stores, sources, and polling only at its session root.",
    scope: throwProductionScope,
) { file in
    guard file.path != throwSessionCompositionPath else { return [] }
    return functionCalls()
        .filter { match in
            guard let name = calledDeclarationName(match.node) else { return false }
            return throwLiveDependencyNames.contains(name)
        }
        .matches(in: file)
        .map { match in
            let name = calledDeclarationName(match.node) ?? "live dependency"
            return match.failure(
                message: "Throw constructs \(name) outside its session composition root.",
                evidence: ViolationEvidence(
                    observed: "\(name)(...) in \(file.path.rawValue)",
                    expectation: "construction in \(throwSessionCompositionPath.rawValue)",
                ),
            )
        }
}

private func calledDeclarationName(_ call: FunctionCallExprSyntax) -> String? {
    if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
        return reference.baseName.text
    }
    if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
        return member.declName.baseName.text
    }
    return nil
}

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

private let throwApplicationLifecycleMethodNames: Set<String> = [
    "applicationDidEnterBackground",
    "applicationWillEnterForeground",
]

private let throwSceneLifecycleRule = Rules.files(
    "throw.controller_scene_lifecycle",
    severity: .error,
    summary: "Throw derives foreground presence from controller scenes.",
    scope: .component(ThrowComponent.throwApp),
) { file in
    SyntaxQuery<FunctionDeclSyntax>()
        .filter { throwApplicationLifecycleMethodNames.contains($0.node.name.text) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw uses an application callback for scene lifecycle.",
                evidence: ViolationEvidence(
                    observed: match.node.name.text,
                    expectation: "typed controller-scene lifecycle delivery",
                ),
            )
        }
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

private let throwLoggingFacadeRule = Rules.files(
    "throw.logging_facade",
    severity: .error,
    summary: "Throw production logging goes through its typed Periscope facade.",
    scope: throwProductionScope,
) { file in
    let rawLoggingImports = SyntaxQuery<ImportDeclSyntax>()
        .filter { ["OSLog", "os"].contains($0.node.path.trimmedDescription) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code imports system logging directly.",
                evidence: ViolationEvidence(
                    observed: match.node.trimmedDescription,
                    expectation: "the typed ThrowLog facade",
                ),
            )
        }

    let rawOutputNames: Set = ["NSLog", "debugPrint", "dump", "print"]
    let rawOutputCalls = functionCalls()
        .filter { rawOutputNames.contains($0.node.calledExpression.trimmedDescription) }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "Throw production code writes diagnostic output directly.",
                evidence: ViolationEvidence(
                    observed: match.node.calledExpression.trimmedDescription,
                    expectation: "a typed ThrowLog event",
                ),
            )
        }

    return rawLoggingImports + rawOutputCalls
}
