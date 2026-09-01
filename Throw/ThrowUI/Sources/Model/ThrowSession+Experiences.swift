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

    public func selectExperience(_ id: ProjectionExperienceID) async {
        await experienceCoordinator.select(id)
    }

    public func selectNextExperience() async {
        await experienceCoordinator.selectNext()
    }

    public func selectPreviousExperience() async {
        await experienceCoordinator.selectPrevious()
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
        for id: ProjectionExperienceID,
    ) {
        do {
            let duration = try ProjectionDwellDuration(seconds: seconds)
            let entries = projectionPlaylist.entries.map { entry in
                entry.experienceID == id
                    ? ProjectionPlaylistEntry(experienceID: id, dwellDuration: duration)
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
        experienceCoordinatorState = state

        guard projectionPlaylist.selectedExperienceID != state.activeExperienceID else { return }
        do {
            projectionPlaylist = try ProjectionPlaylist(
                entries: projectionPlaylist.entries,
                automaticRotationEnabled: projectionPlaylist.automaticRotationEnabled,
                selectedExperienceID: state.activeExperienceID,
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
                if id == .airAndSpace {
                    guard airAndSpaceActivation.activate(lease) else { return }
                    preparedOutputsByExperience.removeValue(forKey: id)
                    if isReconcilingDemand == false {
                        scheduleDemandReconciliation()
                    }
                } else {
                    assertionFailure("An unavailable experience must not be activated")
                }
            case let .deactivate(lease):
                let id = lease.experienceID
                if id == .airAndSpace {
                    guard airAndSpaceActivation.deactivate(lease) else { return }
                }
                if preparedOutputsByExperience[id]?.activationLease == lease {
                    preparedOutputsByExperience.removeValue(forKey: id)
                }
                await projectionWorker.experienceBecameInactive(id, at: dateProvider.now())
                if id == .airAndSpace {
                    await airAndSpaceRuntime.deactivate(
                        lease: lease,
                        reporting: isQuietNow ? .quiet : .idle,
                    )
                }
            case let .beginTransition(from, to):
                await transitionExperience(from: from, to: to)
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
        if let lease = await experienceCoordinator.activationLease(for: .airAndSpace) {
            _ = airAndSpaceActivation.activate(lease)
        }
    }

    private var configuredExperienceIDs: Set<ProjectionExperienceID> {
        setupState.configuredExperienceIDs
    }

    func configureExperienceCoordinator(with playlist: ProjectionPlaylist) async {
        playlistConfigurationTask?.cancel()
        playlistConfigurationTask = nil
        let configuration = nextPlaylistConfiguration(for: playlist)
        await experienceCoordinator.configure(configuration)
    }

    private func replaceProjectionPlaylist(
        entries: [ProjectionPlaylistEntry],
        automaticRotationEnabled: Bool,
    ) {
        do {
            let playlist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: automaticRotationEnabled,
                selectedExperienceID: activeExperienceID ?? projectionPlaylist.selectedExperienceID,
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
    ) async {
        let to = lease.experienceID
        guard from != to else {
            if await experienceCoordinator.commitTransition(to: lease) {
                await experienceCoordinator.completeTransition(to: lease)
            }
            return
        }
        guard projectionPresentationTransition == nil else {
            assertionFailure("A projection presentation transition is already active")
            return
        }
        projectionPresentationTransition = .fadingOut(
            targetLease: lease,
            bufferedTargetUpdate: nil,
        )
        stopRenderer()
        let fadeDuration = ThrowStylesheet.default.projection.experienceTransition.fadeDuration
        withAnimation(.linear(duration: fadeDuration)) {
            projectionSurfaceOpacity = 0
        }
        do {
            try await Task.sleep(for: .seconds(fadeDuration))
        } catch {
            abandonProjectionPresentationTransition()
            return
        }

        guard let prepared = preparedOutputsByExperience[to],
              prepared.activationLease == lease
        else {
            assertionFailure("A projection experience became visible before it was prepared")
            await experienceCoordinator.rejectPreparedTransition(
                lease: lease,
                failure: .decoding,
            )
            abandonProjectionPresentationTransition()
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
        // The active identity and complete frame exchange only while the surface is black.
        applyExperienceCoordinatorState(committedState)
        projectionFrame = prepared.output.frame
        projectionMarkEffects = prepared.output.effects
        observerMapPoint = prepared.output.observerPoint
        geographyLayerHealth = prepared.output.geographyHealth
        let semanticFrame = prepared.semanticFrame
        currentExperienceFrame = semanticFrame
        currentLayerFrame = switch semanticFrame {
            case let .airAndSpace(frame): frame.flights
            case .transit: nil
        }
        feedHealth = experienceHealth[to] ?? .idle
        if preparedOutputsByExperience[to]?.activationLease == lease {
            preparedOutputsByExperience.removeValue(forKey: to)
        }
        guard let transition = projectionPresentationTransition,
              transition.targetLease == lease
        else {
            assertionFailure("The committed projection transition lost its presentation state")
            projectionSurfaceOpacity = 1
            await experienceCoordinator.completeTransition(to: lease)
            restartRenderer()
            return
        }
        projectionPresentationTransition = transition.advancingToFadeIn()
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

    func finishProjectionPresentationTransition(to lease: ProjectionActivationLease) async {
        guard let transition = projectionPresentationTransition,
              transition.targetLease == lease
        else { return }
        let bufferedUpdate = transition.bufferedTargetUpdate
        projectionPresentationTransition = nil
        if let bufferedUpdate {
            await publishVisibleAirAndSpaceUpdate(bufferedUpdate)
        } else {
            restartRenderer()
        }
    }

    private func abandonProjectionPresentationTransition() {
        projectionPresentationTransition = nil
        projectionSurfaceOpacity = 1
        restartRenderer()
    }
}
