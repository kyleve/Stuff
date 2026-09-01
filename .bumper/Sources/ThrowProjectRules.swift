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
    throwProjectedFrameErasureRule
    throwTypedProjectionFamiliesRule
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
private let throwProjectedFrameErasurePath: RelativeFilePath =
    "Throw/ThrowUI/Sources/Projection/ProjectionFrame.swift"
private let throwProjectionModelsPath: RelativeFilePath =
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

private let throwProjectedFrameErasureRule = Rules.files(
    "throw.projected_frame_erasure_ownership",
    severity: .error,
    summary: "Throw erases typed projected frames only at its presentation boundary.",
    scope: throwProductionScope,
) { file in
    guard file.path != throwProjectedFrameErasurePath else { return [] }
    return functionCalls()
        .filter { match in
            guard let name = calledDeclarationName(match.node) else { return false }
            return name == "ProjectedLayer" || name == "ProjectionFrame"
        }
        .matches(in: file)
        .map { match in
            let name = calledDeclarationName(match.node) ?? "projected frame"
            return match.failure(
                message: "Throw constructs \(name) outside its presentation erasure boundary.",
                evidence: ViolationEvidence(
                    observed: "\(name)(...) in \(file.path.rawValue)",
                    expectation: "construction in \(throwProjectedFrameErasurePath.rawValue)",
                ),
            )
        }
}

private let throwProjectionFamilyAliases: [String: (name: String, type: String)] = [
    "FlightsLayerKind": ("MarkElement", "FlightsMarkElement"),
    "GeographyLayerKind": ("LineStyle", "GeographyLineKind"),
    "SatellitesLayerKind": ("MarkElement", "SatelliteMarkElement"),
    "StarsLayerKind": ("MarkElement", "StarMarkElement"),
    "TransitNetworkLayerKind": ("LineStyle", "TransitNetworkLineStyle"),
    "TransitVehiclesLayerKind": ("MarkElement", "TransitVehicleMarkElement"),
]

private let throwTypedProjectionFamiliesRule = Rules.files(
    "throw.typed_projection_families",
    severity: .error,
    summary: "Throw keeps projection element families compiler-checked through presentation.",
    scope: throwProductionScope,
) { file in
    if file.path == throwProjectionModelsPath {
        let aliasFailures = SyntaxQuery<TypeAliasDeclSyntax>()
            .filter { match in
                guard
                    let enumName = enclosingEnumName(match.node),
                    let expected = throwProjectionFamilyAliases[enumName],
                    match.node.name.text == expected.name
                else {
                    return false
                }
                return match.node.initializer.value.trimmedDescription != expected.type
            }
            .matches(in: file)
            .map { match in
                let enumName = enclosingEnumName(match.node) ?? "projection layer kind"
                let expected = throwProjectionFamilyAliases[enumName]
                return match.failure(
                    message: "Throw changes the element family owned by \(enumName).",
                    evidence: ViolationEvidence(
                        observed: match.node.trimmedDescription,
                        expectation: expected.map { "typealias \($0.name) = \($0.type)" }
                            ?? "the declared projection family",
                    ),
                )
            }
        let airportIdentityFailures = SyntaxQuery<EnumCaseElementSyntax>()
            .filter { match in
                guard
                    match.node.name.text == "airport",
                    enclosingEnumName(match.node) == "FlightsMarkElement"
                else {
                    return false
                }
                let parameterTypes = match.node.parameterClause?.parameters
                    .map(\.type.trimmedDescription) ?? []
                return parameterTypes != ["AirportGlyphDescriptor"]
            }
            .matches(in: file)
            .map { match in
                match.failure(
                    message: "Throw stores airport identity separately from its glyph descriptor.",
                    evidence: ViolationEvidence(
                        observed: match.node.trimmedDescription,
                        expectation: "case airport(AirportGlyphDescriptor)",
                    ),
                )
            }
        return aliasFailures + airportIdentityFailures
    }

    guard file.path == throwProjectedFrameErasurePath else { return [] }
    return SyntaxQuery<FunctionDeclSyntax>()
        .filter { $0.node.name.text == "replacingMarks" }
        .matches(in: file)
        .map { match in
            match.failure(
                message: "ThrowUI accepts an erased mark array at its presentation mutation seam.",
                evidence: ViolationEvidence(
                    observed: match.node.signature.trimmedDescription,
                    expectation: "case-preserving presentation-field updates",
                ),
            )
        }
}

private func enclosingEnumName(_ node: some SyntaxProtocol) -> String? {
    var ancestor = Syntax(node).parent
    while let current = ancestor {
        if let declaration = current.as(EnumDeclSyntax.self) {
            return declaration.name.text
        }
        ancestor = current.parent
    }
    return nil
}

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
