#if DEBUG
    import Foundation
    import LifecycleKit
    import Testing
    import WhereCore
    @testable import WhereUI

    @MainActor
    struct DeveloperOnboardingModelTests {
        @Test func completingTheFlowChangesOnlyItsOwnWorld() async throws {
            let live = PreviewSupport.loadedModel()
            let liveScope = live.activeScope
            let liveSession = live.session
            let liveTheme = live.theme
            let liveContext = live.installationRecordingContext
            let preview = makePreview()
            let drive = Task { await preview.run() }
            let handle = try await gate(in: preview)
            #expect(preview.model.activeScope == nil)
            #expect(!preview.model.hasOnboarded)
            #expect(!preview.model.hasConfirmedRecordingChoice)
            let flow = makeFlow(preview, gate: handle)
            flow.selectTheme(.alternate, using: preview.model)
            flow.selection.toggle(.california)
            await flow.discoverRecordingDevices(using: preview.model)
            #expect(preview.model.activeScope == nil)
            flow.finish(using: preview.model)
            await drive.value

            let scope = try #require(preview.model.activeScope)
            #expect(preview.model.hasOnboarded)
            #expect(preview.model.hasConfirmedRecordingChoice)
            #expect(preview.model.theme == .alternate)
            #expect(try await scope.services.primaryRegions().map(\.region) == [.california])
            #expect(await scope.services.ingestor.authorizationStatus() == .always)
            #expect(preview.model.session == nil)
            #expect(scope.logStore == nil)
            #expect(live.activeScope === liveScope)
            #expect(live.session === liveSession)
            #expect(live.theme == liveTheme)
            #expect(live.installationRecordingContext == liveContext)
            await preview.releaseScope()
            #expect(preview.model.activeScope == nil)
        }

        @Test func demoCompletesOnlyThePreviewGate() async throws {
            let preview = makePreview()
            let drive = Task { await preview.run() }
            let flow = try await makeFlow(preview, gate: gate(in: preview))
            flow.enterDemoMode(using: preview.model)
            await drive.value
            #expect(preview.model.isInDemoMode)
            #expect(preview.model.session == nil)
            #expect(!preview.model.hasConfirmedRecordingChoice)
            await preview.releaseScope()
            #expect(preview.model.activeScope == nil)
        }

        @Test func closingAndReopeningStartsFresh() async throws {
            let preview = makePreview()
            let drive = Task { await preview.run() }
            _ = try await gate(in: preview)
            preview.model.previewTheme(.alternate)
            preview.close()
            await drive.value
            await preview.releaseScope()
            let reopened = makePreview()
            #expect(reopened.model.activeScope == nil)
            #expect(!reopened.model.hasOnboarded)
            #expect(!reopened.model.hasConfirmedRecordingChoice)
            #expect(reopened.model.theme == .standard)
            #expect(reopened.model.installationRecordingContext.currentDevice.id
                != preview.model.installationRecordingContext.currentDevice.id)
        }

        @Test func closingDuringStartupDoesNotLeaveAParkedDrive() async {
            let preview = makePreview()
            let drive = Task { await preview.run() }
            await Task.yield()
            preview.close()
            await drive.value
            #expect(preview.model.activeScope == nil)
        }

        @Test func restoringABackupCommitsOnlyToThePreviewStore() async throws {
            let source = makePreview()
            _ = try source.model.confirmInitialRecordingChoice(isEnabled: false)
            let sourceScope = try await source.model.resolveScope()
            try await sourceScope.services.setPrimaryRegions([
                .init(region: .newYork, appearance: nil, order: 0),
            ])
            let archive = try await sourceScope.services.backup.exportBackup()
            defer {
                do { try FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }
                catch { Issue.record(error) }
            }
            let archiveData = try Data(contentsOf: archive)
            let preview = makePreview()
            let drive = Task { await preview.run() }
            let flow = try await makeFlow(preview, gate: gate(in: preview))
            flow.handleRestoreSelection(.success(archive))
            flow.chooseRestoreStrategy(.replace)
            flow.recordingEnabled = false
            flow.finish(using: preview.model)
            await drive.value
            let restored = try #require(preview.model.activeScope)
            #expect(preview.model.hasOnboarded)
            #expect(try await restored.services.primaryRegions().map(\.region) == [.newYork])
            #expect(try Data(contentsOf: archive) == archiveData)
            #expect(preview.model.session == nil)
            await preview.releaseScope()
            await source.releaseScope()
        }

        @Test func privacyDisclosureUsesTheInjectedProcessConfiguration() {
            let diagnostics = DiagnosticReportingConfiguration.defaults(isDebugBuild: false)
            let preview = DeveloperOnboardingModel(
                deviceKind: .tablet,
                diagnostics: diagnostics,
                now: { PreviewSupport.referenceNow },
            )
            #expect(preview.model.diagnosticReporting.effectiveConfiguration == diagnostics)
            #expect(!preview.model.installationRecordingContext.recommendedRecordingEnabled)
        }

        private func makePreview() -> DeveloperOnboardingModel {
            DeveloperOnboardingModel(
                deviceKind: .phone,
                diagnostics: .defaults(isDebugBuild: true),
                now: { PreviewSupport.referenceNow },
            )
        }

        private func makeFlow(
            _ preview: DeveloperOnboardingModel,
            gate: LifecycleGateHandle,
        ) -> OnboardingFlowModel {
            OnboardingFlowModel(
                gate: gate,
                installationContext: preview.model.installationRecordingContext,
                startsAtRecordingChoice: false,
                initialTheme: .standard,
            )
        }

        private func gate(in preview: DeveloperOnboardingModel) async throws
            -> LifecycleGateHandle
        {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while ContinuousClock.now < deadline {
                if case let .awaitingGate(handle) = preview.runner.phase { return handle }
                try await Task.sleep(for: .milliseconds(1))
            }
            throw GateTimeout()
        }

        private struct GateTimeout: Error {}
    }
#endif
