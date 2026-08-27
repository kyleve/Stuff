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

    public func pauseExperienceRotation() {
        Task(name: "Throw pause View rotation") { [experienceCoordinator] in
            await experienceCoordinator.pause()
        }
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
        activeExperienceID = state.activeExperienceID
        requestedExperienceID = state.requestedExperienceID
        nextExperienceID = state.nextExperienceID
        prewarmingExperienceID = state.prewarmingExperienceID
        isExperienceRotationPaused = state.isPaused
        experienceDwellEndsAt = state.dwellEndsAt
        experienceHealth = state.healthByExperience
        experienceSelectionFailure = state.manualSelectionFailure

        guard projectionPlaylist.selectedExperienceID != state.activeExperienceID else { return }
        do {
            projectionPlaylist = try ProjectionPlaylist(
                entries: projectionPlaylist.entries,
                automaticRotationEnabled: projectionPlaylist.automaticRotationEnabled,
                selectedExperienceID: state.activeExperienceID,
                configuredExperienceIDs: configuredExperienceIDs,
                catalog: .standard,
            )
            schedulePreferencesSave()
        } catch {
            reportPlaylistFailure(error)
        }
    }

    func applyExperienceCoordinatorAction(
        _ action: ProjectionExperienceCoordinatorAction,
    ) async {
        switch action {
            case let .activate(id, generation, _):
                if id == .airAndSpace {
                    airAndSpaceActivationGeneration = generation
                    if isReconcilingDemand == false {
                        scheduleDemandReconciliation()
                    }
                } else {
                    assertionFailure("An unavailable experience must not be activated")
                }
            case let .deactivate(id):
                await projectionWorker.experienceBecameInactive(id, at: dateProvider.now())
                if id == .airAndSpace {
                    await airAndSpaceRuntime.deactivate(
                        reporting: isQuietNow ? .quiet : .idle,
                    )
                }
            case let .beginTransition(from, to, generation):
                await transitionExperience(from: from, to: to, generation: generation)
        }
    }

    func reconcileExperienceDemand(isQuiet: Bool) async {
        await experienceCoordinator.reconcile(
            demand: ProjectionExperienceDemand(
                hasOutput: outputDemands.isEmpty == false,
                isForeground: isForeground,
                isQuiet: isQuiet,
                isCalibrating: isCalibrating,
            ),
        )
        if let generation = await experienceCoordinator.activationGeneration(for: .airAndSpace) {
            airAndSpaceActivationGeneration = generation
        }
    }

    private var configuredExperienceIDs: Set<ProjectionExperienceID> {
        selectedSourceConfiguration == validatedSourceConfiguration &&
            selectedSourceConfiguration != nil
            ? [.airAndSpace]
            : []
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
            schedulePreferencesSave()
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
            settingsFailure = String(localized: .viewsPlaylistApplyFailed)
            return
        }
        settingsFailure = playlistError.localizedSettingsDescription
    }

    private func transitionExperience(
        from: ProjectionExperienceID,
        to: ProjectionExperienceID,
        generation: UInt64,
    ) async {
        guard from != to else {
            if await experienceCoordinator.commitTransition(to: to, generation: generation) {
                await experienceCoordinator.completeTransition(to: to, generation: generation)
            }
            return
        }
        let fadeDuration = ThrowStylesheet.default.projection.experienceTransition.fadeDuration
        withAnimation(.linear(duration: fadeDuration)) {
            projectionSurfaceOpacity = 0
        }
        do {
            try await Task.sleep(for: .seconds(fadeDuration))
        } catch {
            projectionSurfaceOpacity = 1
            return
        }

        guard let prepared = preparedOutputsByExperience[to] else {
            assertionFailure("A projection experience became visible before it was prepared")
            projectionSurfaceOpacity = 1
            return
        }
        guard await experienceCoordinator.commitTransition(to: to, generation: generation) else {
            withAnimation(.linear(duration: fadeDuration)) {
                projectionSurfaceOpacity = 1
            }
            return
        }
        // The active identity and complete frame exchange only while the surface is black.
        activeExperienceID = to
        projectionFrame = prepared.frame
        projectionMarkEffects = prepared.effects
        observerMapPoint = prepared.observerPoint
        geographyLayerHealth = prepared.geographyHealth
        if let semanticFrame = semanticFramesByExperience[to] {
            currentExperienceFrame = semanticFrame
            currentLayerFrame = semanticFrame.layers.first { $0.layerID == .flights }
        }
        feedHealth = experienceHealth[to] ?? .idle
        preparedOutputsByExperience.removeValue(forKey: to)
        withAnimation(.linear(duration: fadeDuration)) {
            projectionSurfaceOpacity = 1
        }
        do {
            try await Task.sleep(for: .seconds(fadeDuration))
        } catch {
            projectionSurfaceOpacity = 1
            return
        }
        await experienceCoordinator.completeTransition(to: to, generation: generation)
        restartRenderer()
    }
}
