import Foundation
import ThrowCore

extension ThrowSession {
    private struct TransitCenterOffset {
        let east: Double
        let north: Double
    }

    public var transitMapCenterEastOffset: Double {
        transitMapCenterOffset.east
    }

    public var transitMapCenterNorthOffset: Double {
        transitMapCenterOffset.north
    }

    public func updateTransitMapCenterOffset(east: Double, north: Double) {
        do {
            let boundedEast = min(max(east, -50), 50)
            let boundedNorth = min(max(north, -50), 50)
            let distance = try NauticalMiles(value: hypot(boundedEast, boundedNorth))
            let center = try ProjectionEngine().destination(
                from: TransitPreferences.defaultValue.mapCenter,
                bearing: Bearing(degrees: atan2(boundedEast, boundedNorth) * 180 / .pi),
                distance: distance,
            )
            updateTransitPreferences(transitPreferences.replacingMapCenter(center))
        } catch {
            recordPostLaunchFailure(.playlist(nil), error: error)
        }
    }

    func applyTransitUpdate(_ update: TransitRuntimeUpdate) async {
        guard let activationLease = update.activationLease,
              activationLease == transitActivation.activeLease
        else { return }
        let transitFrame = update.transitFrame
        replacePendingTransitFrame(transitFrame)
        let semanticFrame = ProjectionExperienceFrame.transit(transitFrame)

        await experienceCoordinator.reportRuntimeUpdate(
            lease: activationLease,
            successfulLease: update.successfulActivationLease,
            health: update.health,
        )
        let awaitsPreparation = await experienceCoordinator.isAwaitingPreparation(
            activationLease,
        )
        if update.successfulActivationLease == activationLease, awaitsPreparation {
            do {
                let contextGeneration = projectionContextGeneration
                let output = try await projectedOutput(
                    for: semanticFrame,
                    generatedAt: dateProvider.now(),
                    revision: projectionInputRevision,
                    loggingOperation: .projectionPreparation,
                )
                guard let currentRequest = try? projectionRequest(
                    for: .transit(pendingTransitFrame),
                    generatedAt: output.request.generatedAt,
                    revision: projectionInputRevision,
                    loggingOperation: .projectionPreparation,
                ) else { return }
                guard transitActivation.activeLease == activationLease,
                      projectionContextGeneration == contextGeneration,
                      output.request == currentRequest,
                      await experienceCoordinator.isAwaitingPreparation(activationLease)
                else { return }
                guard let prepared = PreparedProjectionPresentation.rendered(
                    contextGeneration: contextGeneration,
                    activationLease: activationLease,
                    output: output,
                ) else {
                    assertionFailure("A worker output must match its activation lease")
                    return
                }
                projectionPresentationStaging = .prepared(prepared)
                let accepted = await experienceCoordinator.reportRuntimePrepared(
                    activationLease,
                )
                guard projectionContextGeneration == contextGeneration,
                      transitActivation.activeLease == activationLease,
                      projectionPresentationStaging?.preparedProjection == prepared
                else {
                    await experienceCoordinator.invalidatePreparedTransition(
                        lease: activationLease,
                    )
                    return
                }
                if accepted == false,
                   case let .prepared(currentPrepared) = projectionPresentationStaging,
                   currentPrepared == prepared
                {
                    projectionPresentationStaging = nil
                }
                if accepted { resolvePostLaunchFailure(.projectionPreparation) }
            } catch is CancellationError {
                return
            } catch {
                recordPostLaunchFailure(.projectionPreparation, error: error)
                await experienceCoordinator.reportRuntimeUpdate(
                    lease: activationLease,
                    successfulLease: nil,
                    health: .failed(.decoding),
                )
                return
            }
        }

        if let staging = projectionPresentationStaging, staging.isTransitioning {
            projectionPresentationStaging = staging.buffering(.transit(update))
            return
        }
        await publishVisibleTransitUpdate(update)
    }

    func publishVisibleTransitUpdate(_ update: TransitRuntimeUpdate) async {
        guard let activationLease = update.activationLease,
              activationLease == transitActivation.activeLease,
              activeExperienceID == .transit
        else { return }
        let previousHadContent: Bool = switch visibleProjection.semanticFrame {
            case let .transit(frame): frame.network != nil || frame.vehicles != nil
            case .airAndSpace, nil: false
        }
        publishExperienceHealth(update.health, for: .transit)
        let frame = update.transitFrame
        if frame.network != nil || frame.vehicles != nil {
            restartRenderer()
        } else if previousHadContent || update.health.visibleContentCount == 0 {
            await clearTransitProjectionState(restartsGeography: true)
            publishExperienceHealth(update.health, for: .transit)
        }
    }

    /// Downloads the current MTA schedule and verifies at least one realtime partition.
    public func configureNewYorkTransit() async -> Bool {
        guard let preferenceProducer = beginPreferenceMutation() else { return false }
        defer { finishPreferenceMutation(preferenceProducer) }
        await waitForPreferenceSaveWorker()

        do {
            try await transitRuntime.validateConnection()
            try Task.checkCancellation()
        } catch is CancellationError {
            return false
        } catch {
            recordPostLaunchFailure(.playlist(nil), error: error)
            return false
        }

        let persistence = await persistReconciledPreferenceMutation(
            failure: .playlist(nil),
            makeMutation: configuredTransitMutation,
            prepareForPublication: {
                self.prepareProjectionPreferencePublication(.transitConfiguration)
            },
            publish: { _ in },
        )
        guard case let .committed(invalidation) = persistence else { return false }
        _ = await finishProjectionPreferenceInvalidation(invalidation)
        await configureExperienceCoordinator(with: projectionPlaylist)
        completeProjectionPreferenceInvalidation(invalidation)
        resolvePostLaunchFailure(.playlist)
        scheduleDemandReconciliation()
        return true
    }

    public func removeTransit() async {
        guard let preferenceProducer = beginPreferenceMutation() else { return }
        defer { finishPreferenceMutation(preferenceProducer) }
        await waitForPreferenceSaveWorker()

        let persistence = await persistReconciledPreferenceMutation(
            failure: .playlist(nil),
            makeMutation: removedTransitMutation,
            prepareForPublication: {
                self.prepareProjectionPreferencePublication(.transitConfiguration)
            },
            publish: { _ in },
        )
        guard case let .committed(invalidation) = persistence else { return }
        _ = await finishProjectionPreferenceInvalidation(invalidation)
        await configureExperienceCoordinator(with: projectionPlaylist)
        completeProjectionPreferenceInvalidation(invalidation)
        resolvePostLaunchFailure(.playlist)
        scheduleDemandReconciliation()
    }

    func reconcileTransitDemand(
        preReconcileLease: ProjectionActivationLease?,
        authoritativeLease: ProjectionActivationLease?,
        generation: ProjectionDemandGeneration,
        reporting health: FeedHealth,
    ) async {
        guard generation == demandGeneration,
              projectionPreferenceInvalidation == nil
        else { return }
        guard launchState.isOperational,
              transitPreferences.isConfigured,
              let activationLease = authoritativeLease
        else {
            if let authoritativeLease {
                await suspendTransitPolling(
                    lease: authoritativeLease,
                    generation: generation,
                    reporting: health,
                )
            } else if let preReconcileLease {
                await transitRuntime.deactivate(lease: preReconcileLease, reporting: health)
            }
            guard generation == demandGeneration else { return }
            if visibleProjection.experienceID == .transit {
                await clearTransitProjectionState(restartsGeography: false)
                publishExperienceHealth(health, for: .transit)
            }
            return
        }

        let activation = await transitRuntime.activate(
            labelMode: transitPreferences.labelMode,
            lease: activationLease,
            demandGeneration: generation,
        )
        guard generation == demandGeneration,
              projectionPreferenceInvalidation == nil
        else { return }
        guard transitActivation.activeLease == activationLease else {
            scheduleDemandReconciliation()
            return
        }
        switch activation {
            case let .accepted(update):
                guard update.activationLease == activationLease else {
                    assertionFailure("An accepted Transit activation must match its request")
                    return
                }
            case .superseded:
                scheduleDemandReconciliation()
        }
    }

    private func suspendTransitPolling(
        lease: ProjectionActivationLease,
        generation: ProjectionDemandGeneration,
        reporting health: FeedHealth,
    ) async {
        let result = await transitRuntime.suspendPolling(
            lease: lease,
            demandGeneration: generation,
            reporting: health,
        )
        if case .superseded = result { scheduleDemandReconciliation() }
    }

    func replacePendingTransitFrame(_ frame: TransitExperienceFrame) {
        guard pendingTransitFrame != frame else { return }
        pendingTransitFrame = frame
        projectionInputRevision = projectionInputRevision.successor()
    }

    private func clearTransitProjectionState(restartsGeography: Bool) async {
        replacePendingTransitFrame(.empty)
        stopRenderer()
        let visible = visibleProjection.cleared(
            mode: projectionMode,
            generatedAt: dateProvider.now(),
        )
        guard let presentation = projectionPresentationState.replacingVisible(visible) else {
            assertionFailure("Clearing Transit must preserve its visible identity")
            return
        }
        projectionPresentationState = presentation
        await projectionWorker.reset(experienceID: .transit)
        if restartsGeography, transitGeographyEnabled, activeExperienceID == .transit {
            restartRenderer()
        }
    }

    private var transitMapCenterOffset: TransitCenterOffset {
        let defaultCenter = TransitPreferences.defaultValue.mapCenter
        do {
            let position = try ProjectionEngine().greatCirclePosition(
                from: defaultCenter,
                to: transitMapCenter,
            )
            let bearing = position.initialBearing.degrees * .pi / 180
            return TransitCenterOffset(
                east: position.distance.value * sin(bearing),
                north: position.distance.value * cos(bearing),
            )
        } catch {
            assertionFailure("Validated transit map centers must produce an offset")
            return TransitCenterOffset(east: 0, north: 0)
        }
    }

    private func configuredTransitMutation(
        from base: ThrowPreferenceSnapshot,
    ) throws -> ThrowPreferenceMutation<Void> {
        let transit = base.transitPreferences.replacingConfiguration(
            .configured(cityID: .newYorkCity),
        )
        var configuredExperienceIDs = base.setupState.configuredExperienceIDs
        configuredExperienceIDs.insert(.transit)
        let playlist: ProjectionPlaylist = if base.projectionPlaylist.entry(for: .transit) == nil {
            try base.projectionPlaylist.addingConfiguredExperience(
                .transit,
                dwellDuration: .defaultValue,
                configuredExperienceIDs: configuredExperienceIDs,
                catalog: .standard,
            )
        } else {
            base.projectionPlaylist
        }
        return ThrowPreferenceMutation(
            snapshot: ThrowPreferenceSnapshot(
                setupState: base.setupState,
                globalPreferences: base.globalPreferences,
                airAndSpacePreferences: base.airAndSpacePreferences,
                transitPreferences: transit,
                projectionPlaylist: playlist,
            ),
            publication: (),
        )
    }

    private func removedTransitMutation(
        from base: ThrowPreferenceSnapshot,
    ) throws -> ThrowPreferenceMutation<Void> {
        let entries = base.projectionPlaylist.entries.filter {
            $0.runnableExperienceID != .transit
        }
        let selectedExperienceID: RunnableProjectionExperienceID? = if base.projectionPlaylist
            .selectedRunnableExperienceID == .transit
        {
            entries.first?.runnableExperienceID
        } else {
            base.projectionPlaylist.selectedRunnableExperienceID
        }
        let playlist = try ProjectionPlaylist(
            entries: entries,
            automaticRotationEnabled: base.projectionPlaylist.automaticRotationEnabled &&
                entries.count > 1,
            selectedExperienceID: selectedExperienceID,
            configuredExperienceIDs: base.setupState.configuredExperienceIDs,
            catalog: .standard,
        )
        return ThrowPreferenceMutation(
            snapshot: ThrowPreferenceSnapshot(
                setupState: base.setupState,
                globalPreferences: base.globalPreferences,
                airAndSpacePreferences: base.airAndSpacePreferences,
                transitPreferences: base.transitPreferences.replacingConfiguration(.unconfigured),
                projectionPlaylist: playlist,
            ),
            publication: (),
        )
    }

    #if DEBUG
        @_spi(Testing) public func replaceTransitPreferencesForTesting(
            _ preferences: TransitPreferences,
            playlist: ProjectionPlaylist,
        ) {
            transitPreferences = preferences
            projectionPlaylist = playlist
            projectionInputRevision = projectionInputRevision.successor()
        }
    #endif
}
