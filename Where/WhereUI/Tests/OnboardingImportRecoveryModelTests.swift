import Foundation
import Testing
@_spi(Testing) import WhereCore
@_spi(Testing) @testable import WhereUI

@MainActor
struct OnboardingImportRecoveryModelTests {
    @Test func noMarkerPreservesTheOrdinaryOnboardingDecision() async {
        let model = OnboardingImportRecoveryModel(
            installationContextStore: InMemoryInstallationRecordingContextStore(
                context: .testing,
            ),
        )
        var resolvedScope = false

        let needsOnboarding = await model.recoverInterruptedImport(
            requiresOnboarding: true,
            resolveScope: {
                resolvedScope = true
                throw UnexpectedScopeResolution()
            },
            endSession: {},
            completeOnboarding: {},
        )

        #expect(needsOnboarding)
        #expect(!resolvedScope)
        #expect(model.takeInterruptedImportError() == nil)
    }
}

private struct UnexpectedScopeResolution: Error {}
