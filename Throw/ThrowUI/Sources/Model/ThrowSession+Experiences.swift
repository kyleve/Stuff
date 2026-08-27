import SwiftUI
import ThrowCore

extension ThrowSession {
    public var activeExperienceHealth: FeedHealth {
        if feedHealth == .quiet { return .quiet }
        guard let activeExperienceID else { return .idle }
        return health(for: activeExperienceID)
    }

    public func health(for id: ProjectionExperienceID) -> FeedHealth {
        if let health = experienceHealth[id] { return health }
        return id == .airAndSpace ? feedHealth : .idle
    }

    public var experienceRotationHasControls: Bool {
        projectionPlaylist.entries.count > 1
    }

    public func selectExperience(_ id: RunnableProjectionExperienceID) async {
        await performExperienceSelection(.experience(id))
    }

    public func selectNextExperience() async {
        await performExperienceSelection(.next)
    }

    public func selectPreviousExperience() async {
        await performExperienceSelection(.previous)
    }

    public func pauseExperienceRotation() async {
        await experienceCoordinator.pause()
    }

    public func resumeExperienceRotation() async {
        await experienceCoordinator.resume()
    }

    public func setAutomaticExperienceRotationEnabled(_ isEnabled: Bool) {
        replaceProjectionPlaylist(
            entries: projectionPlaylist.entries,
            automaticRotationEnabled: isEnabled,
        )
    }

    public func setExperienceDwellDuration(
        seconds: Int,
        for id: RunnableProjectionExperienceID,
    ) {
        do {
            let duration = try ProjectionDwellDuration(seconds: seconds)
            let entries = projectionPlaylist.entries.map { entry in
                entry.runnableExperienceID == id
                    ? ProjectionPlaylistEntry(
                        runnableExperienceID: entry.runnableExperienceID,
                        dwellDuration: duration,
                    )
                    : entry
            }
            replaceProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: projectionPlaylist.automaticRotationEnabled,
            )
        } catch {
            reportPlaylistFailure(error)
        }
    }

    public func moveExperience(fromOffsets: IndexSet, toOffset: Int) {
        var entries = projectionPlaylist.entries
        entries.move(fromOffsets: fromOffsets, toOffset: toOffset)
        replaceProjectionPlaylist(
            entries: entries,
            automaticRotationEnabled: projectionPlaylist.automaticRotationEnabled,
        )
    }

    func applyExperienceCoordinatorState(_ state: ProjectionExperienceCoordinatorState) {
        guard experienceCoordinatorState != state else { return }
        guard let presentation = projectionPresentationState.updatingCoordinator(state) else {
            if projectionPresentationStaging?.isTransitioning == true,
               projectionPresentationStaging?.targetLease.experienceID ==
               state.activeExperienceID
            {
                return
            }
            if projectionPreferenceInvalidation != nil {
                replaceProjectionPresentationWithPlaceholder(coordinator: state)
                return
            }
            assertionFailure("A coordinator update cannot change the visible identity")
            return
        }
        projectionPresentationState = presentation
    }

    private func performExperienceSelection(_ command: ExperienceSelectionCommand) async {
        guard let preferenceProducer = beginPreferenceProducer(.experienceSelection) else {
            return
        }
        defer { finishPreferenceProducer(preferenceProducer) }

        switch command {
            case let .experience(id):
                await experienceCoordinator.select(id)
            case .next:
                await experienceCoordinator.selectNext()
            case .previous:
                await experienceCoordinator.selectPrevious()
        }
        let state = await experienceCoordinator.currentState()
        applyExperienceCoordinatorState(state)
        applyExperienceSelection(
            state.activeExperienceID,
            preferenceProducer: preferenceProducer,
        )
    }

    private func applyExperienceSelection(
        _ activeExperienceID: ProjectionExperienceID?,
        preferenceProducer: ThrowPreferenceProducerLease,
    ) {
        switch preferenceProducer.kind {
            case .experienceSelection, .experienceTransition:
                break
            case .mutation:
                preconditionFailure("A mutation producer cannot publish a View selection")
        }
        guard projectionPlaylist.selectedExperienceID != activeExperienceID else { return }
        let selectedRunnableExperienceID = activeExperienceID.flatMap(
            projectionPlaylist.runnableExperienceID(for:),
        )
        guard activeExperienceID == nil || selectedRunnableExperienceID != nil else {
            assertionFailure("The active View must have a runnable playlist identity")
            return
        }
        do {
            projectionPlaylist = try ProjectionPlaylist(
                entries: projectionPlaylist.entries,
                automaticRotationEnabled: projectionPlaylist.automaticRotationEnabled,
                selectedExperienceID: selectedRunnableExperienceID,
                configuredExperienceIDs: configuredExperienceIDs,
                catalog: .standard,
            )
            schedulePreferencesSave(failure: .playlist(nil))
        } catch {
            reportPlaylistFailure(error)
        }
    }

    func applyExperienceCoordinatorAction(
        _ action: ProjectionExperienceCoordinatorAction,
    ) async {
        switch action {
            case let .activate(lease, _):
                let id = lease.experienceID
                guard projectionPreferenceInvalidation == nil else { return }
                switch lease.runnableExperienceID {
                    case .airAndSpace:
                        guard airAndSpaceActivation.activate(lease) else { return }
                    case .transit:
                        guard transitActivation.activate(lease) else { return }
                    #if DEBUG
                        case .testing:
                            assertionFailure("A test-only experience has no production runtime")
                    #endif
                }
                if projectionPresentationStaging?.preparedProjection.experienceID == id {
                    revokeStagedProjection()
                }
                if isReconcilingDemand == false {
                    scheduleDemandReconciliation()
                }
            case let .deactivate(lease):
                let id = lease.experienceID
                switch lease.runnableExperienceID {
                    case .airAndSpace:
                        guard airAndSpaceActivation.deactivate(lease) else { return }
                    case .transit:
                        guard transitActivation.deactivate(lease) else { return }
                    #if DEBUG
                        case .testing:
                            break
                    #endif
                }
                if projectionPresentationStaging?.targetLease == lease {
                    revokeStagedProjection()
                }
                await projectionWorker.experienceBecameInactive(id, at: dateProvider.now())
                switch lease.runnableExperienceID {
                    case .airAndSpace:
                        await airAndSpaceRuntime.deactivate(
                            lease: lease,
                            reporting: isQuietNow ? .quiet : .idle,
                        )
                    case .transit:
                        await transitRuntime.deactivate(
                            lease: lease,
                            reporting: isQuietNow ? .quiet : .idle,
                        )
                    #if DEBUG
                        case .testing:
                            break
                    #endif
                }
            case let .beginTransition(from, to):
                guard let preferenceProducer = beginPreferenceProducer(.experienceTransition)
                else {
                    await experienceCoordinator.invalidatePreparedTransition(lease: to)
                    return
                }
                defer { finishPreferenceProducer(preferenceProducer) }
                await transitionExperience(
                    from: from.experienceID,
                    to: to,
                    preferenceProducer: preferenceProducer,
                )
        }
    }

    func reconcileExperienceDemand(isQuiet: Bool) async {
        await experienceCoordinator.reconcile(
            demand: ProjectionExperienceDemand(
                hasOutput: outputDemands.isEmpty == false,
                isForeground: hasForegroundControllerScene,
                isQuiet: isQuiet,
                isCalibrating: isCalibrating,
            ),
        )
        guard projectionPreferenceInvalidation == nil else { return }
        let authoritativeAirAndSpaceLease = await experienceCoordinator.activationLease(
            for: .airAndSpace,
        )
        let authoritativeTransitLease = await experienceCoordinator.activationLease(for: .transit)
        guard projectionPreferenceInvalidation == nil else { return }
        airAndSpaceActivation.synchronize(with: authoritativeAirAndSpaceLease)
        transitActivation.synchronize(with: authoritativeTransitLease)
    }

    private var configuredExperienceIDs: Set<RunnableProjectionExperienceID> {
        var ids = setupState.configuredExperienceIDs
        if transitPreferences.isConfigured { ids.insert(.transit) }
        return ids
    }

    func configureExperienceCoordinator(with playlist: ProjectionPlaylist) async {
        playlistConfigurationTask?.cancel()
        playlistConfigurationTask = nil
        let configuration = nextPlaylistConfiguration(for: playlist)
        await experienceCoordinator.configure(configuration)
        let state = await experienceCoordinator.currentState()
        applyExperienceCoordinatorState(state)
        let authoritativeAirAndSpaceLease = await experienceCoordinator.activationLease(
            for: .airAndSpace,
        )
        let authoritativeTransitLease = await experienceCoordinator.activationLease(for: .transit)
        airAndSpaceActivation.synchronize(with: authoritativeAirAndSpaceLease)
        transitActivation.synchronize(with: authoritativeTransitLease)
    }

    private func replaceProjectionPlaylist(
        entries: [ProjectionPlaylistEntry],
        automaticRotationEnabled: Bool,
    ) {
        let selectedRunnableExperienceID = activeExperienceID.flatMap(
            projectionPlaylist.runnableExperienceID(for:),
        ) ?? projectionPlaylist.selectedRunnableExperienceID
        do {
            let playlist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: automaticRotationEnabled,
                selectedExperienceID: selectedRunnableExperienceID,
                configuredExperienceIDs: configuredExperienceIDs,
                catalog: .standard,
            )
            projectionPlaylist = playlist
            schedulePreferencesSave(failure: .playlist(nil))
            scheduleExperienceCoordinatorConfiguration(for: playlist)
        } catch {
            reportPlaylistFailure(error)
        }
    }

    private func scheduleExperienceCoordinatorConfiguration(for playlist: ProjectionPlaylist) {
        let configuration = nextPlaylistConfiguration(for: playlist)
        playlistConfigurationTask?.cancel()
        playlistConfigurationTask = Task(name: "Throw configure View playlist") {
            [experienceCoordinator] in
            guard Task.isCancelled == false else { return }
            await experienceCoordinator.configure(configuration)
        }
    }

    private func nextPlaylistConfiguration(
        for playlist: ProjectionPlaylist,
    ) -> ProjectionPlaylistConfiguration {
        playlistConfigurationRevision = playlistConfigurationRevision.successor()
        return ProjectionPlaylistConfiguration(
            playlist: playlist,
            revision: playlistConfigurationRevision,
        )
    }

    private func reportPlaylistFailure(_ error: any Error) {
        guard let playlistError = error as? ProjectionPlaylistError else {
            assertionFailure("Playlist mutation failed with an unexpected error: \(error)")
            recordPostLaunchFailure(.playlist(nil), error: error)
            return
        }
        recordPostLaunchFailure(.playlist(playlistError), error: error)
    }

    private func transitionExperience(
        from: ProjectionExperienceID,
        to lease: ProjectionActivationLease,
        preferenceProducer: ThrowPreferenceProducerLease,
    ) async {
        let to = lease.experienceID
        guard let staged = projectionPresentationStaging,
              let fadingOut = staged.beginningTransition(
                  to: lease,
                  in: projectionContextGeneration,
              )
        else {
            await experienceCoordinator.invalidatePreparedTransition(lease: lease)
            return
        }
        let prepared = fadingOut.preparedProjection
        guard from != to else {
            guard let committedState = await experienceCoordinator.commitTransitionState(to: lease)
            else {
                revokeStagedProjection()
                return
            }
            guard projectionContextGeneration == prepared.contextGeneration,
                  projectionPresentationStaging?.preparedProjection == prepared,
                  publishPreparedProjection(
                      prepared,
                      coordinator: committedState,
                      preferenceProducer: preferenceProducer,
                  )
            else {
                replaceCommittedProjectionWithPlaceholder(
                    coordinator: committedState,
                    preferenceProducer: preferenceProducer,
                )
                await experienceCoordinator.completeTransition(to: lease)
                return
            }
            projectionPresentationStaging = nil
            await experienceCoordinator.completeTransition(to: lease)
            restartRenderer()
            return
        }
        projectionPresentationStaging = fadingOut
        stopRenderer()
        let fadeDuration = ThrowStylesheet.default.projection.experienceTransition.fadeDuration
        withAnimation(.linear(duration: fadeDuration)) {
            projectionSurfaceOpacity = 0
        }
        do {
            #if DEBUG
                if let waitForProjectionFadeOutForTesting {
                    await waitForProjectionFadeOutForTesting()
                    try Task.checkCancellation()
                } else {
                    try await Task.sleep(for: .seconds(fadeDuration))
                }
            #else
                try await Task.sleep(for: .seconds(fadeDuration))
            #endif
        } catch is CancellationError {
            if currentFadeOut(for: prepared) != nil {
                abandonProjectionPresentationTransition()
            }
            return
        } catch {
            assertionFailure("The projection fade timer failed: \(error)")
            abandonProjectionPresentationTransition()
            return
        }

        guard currentFadeOut(for: prepared) != nil else {
            await experienceCoordinator.invalidatePreparedTransition(lease: lease)
            return
        }
        guard let committedState = await experienceCoordinator.commitTransitionState(to: lease)
        else {
            withAnimation(.linear(duration: fadeDuration)) {
                projectionSurfaceOpacity = 1
            }
            abandonProjectionPresentationTransition()
            return
        }
        guard currentFadeOut(for: prepared) != nil else {
            replaceCommittedProjectionWithPlaceholder(
                coordinator: committedState,
                preferenceProducer: preferenceProducer,
            )
            await experienceCoordinator.completeTransition(to: lease)
            return
        }
        guard commitPreparedProjectionAtBlack(
            coordinator: committedState,
            preferenceProducer: preferenceProducer,
        ) else {
            assertionFailure("A prepared projection must match its committed identity")
            await experienceCoordinator.rejectPreparedTransition(
                lease: lease,
                failure: .decoding,
            )
            abandonProjectionPresentationTransition()
            return
        }
        guard let transition = currentFadeOut(for: prepared),
              let fadingIn = transition.advancingToFadeIn()
        else {
            assertionFailure("The committed projection transition lost its presentation state")
            projectionSurfaceOpacity = 1
            await experienceCoordinator.completeTransition(to: lease)
            restartRenderer()
            return
        }
        projectionPresentationStaging = fadingIn
        withAnimation(.linear(duration: fadeDuration)) {
            projectionSurfaceOpacity = 1
        }
        do {
            try await Task.sleep(for: .seconds(fadeDuration))
        } catch {
            projectionSurfaceOpacity = 1
            await experienceCoordinator.completeTransition(to: lease)
            await finishProjectionPresentationTransition(to: lease)
            return
        }
        await experienceCoordinator.completeTransition(to: lease)
        await finishProjectionPresentationTransition(to: lease)
    }

    @discardableResult
    func commitPreparedProjectionAtBlack(
        coordinator: ProjectionExperienceCoordinatorState,
        preferenceProducer: ThrowPreferenceProducerLease,
    ) -> Bool {
        guard let staging = projectionPresentationStaging,
              staging.isFadingOut,
              staging.contextGeneration == projectionContextGeneration
        else { return false }
        return publishPreparedProjection(
            staging.preparedProjection,
            coordinator: coordinator,
            preferenceProducer: preferenceProducer,
        )
    }

    private func publishPreparedProjection(
        _ prepared: PreparedProjectionPresentation,
        coordinator: ProjectionExperienceCoordinatorState,
        preferenceProducer: ThrowPreferenceProducerLease,
    ) -> Bool {
        let lease = prepared.activationLease
        guard prepared.contextGeneration == projectionContextGeneration,
              let presentation = ProjectionPresentationState.committing(
                  coordinator: coordinator,
                  visible: prepared.visible,
              )
        else { return false }
        // The active identity and complete frame exchange in one assignment while black.
        projectionPresentationState = presentation
        applyExperienceSelection(
            coordinator.activeExperienceID,
            preferenceProducer: preferenceProducer,
        )
        feedHealth = experienceHealth[lease.experienceID] ?? .idle
        return true
    }

    func finishProjectionPresentationTransition(to lease: ProjectionActivationLease) async {
        guard let transition = projectionPresentationStaging,
              transition.isTransitioning,
              transition.targetLease == lease,
              transition.contextGeneration == projectionContextGeneration
        else { return }
        let bufferedUpdate = transition.bufferedTargetUpdate
        projectionPresentationStaging = nil
        if let bufferedUpdate {
            switch bufferedUpdate {
                case let .airAndSpace(update):
                    await publishVisibleAirAndSpaceUpdate(update)
                case let .transit(update):
                    await publishVisibleTransitUpdate(update)
            }
        } else {
            restartRenderer()
        }
    }

    private func abandonProjectionPresentationTransition() {
        projectionPresentationStaging = nil
        projectionSurfaceOpacity = 1
        restartRenderer()
    }

    func revokeStagedProjection() {
        let restoresSurface = projectionPresentationStaging?.isTransitioning == true
        projectionPresentationStaging = nil
        guard restoresSurface else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            projectionSurfaceOpacity = 1
        }
    }

    private func currentFadeOut(
        for prepared: PreparedProjectionPresentation,
    ) -> ProjectionPresentationStaging? {
        guard projectionContextGeneration == prepared.contextGeneration,
              let staging = projectionPresentationStaging,
              staging.isFadingOut,
              staging.preparedProjection == prepared
        else { return nil }
        return staging
    }

    private func replaceProjectionPresentationWithPlaceholder(
        coordinator: ProjectionExperienceCoordinatorState,
    ) {
        let preferredExperienceID = coordinator.activeExperienceID ?? visibleProjection.experienceID
        projectionPresentationState = .initial(
            coordinator: coordinator,
            preferredExperienceID: preferredExperienceID,
            mode: projectionMode,
            generatedAt: dateProvider.now(),
        )
    }

    private func replaceCommittedProjectionWithPlaceholder(
        coordinator: ProjectionExperienceCoordinatorState,
        preferenceProducer: ThrowPreferenceProducerLease,
    ) {
        replaceProjectionPresentationWithPlaceholder(coordinator: coordinator)
        applyExperienceSelection(
            coordinator.activeExperienceID,
            preferenceProducer: preferenceProducer,
        )
    }
}

private enum ExperienceSelectionCommand {
    case experience(RunnableProjectionExperienceID)
    case next
    case previous
}
