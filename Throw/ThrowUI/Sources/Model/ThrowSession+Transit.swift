import Foundation
import ThrowCore

extension ThrowSession {
    private struct TransitCenterOffset {
        let east: Double
        let north: Double
    }

    public var transitMapCenterEastOffset: Double {
        get { transitMapCenterOffset.east }
        set { setTransitMapCenterOffset(east: newValue, north: transitMapCenterOffset.north) }
    }

    public var transitMapCenterNorthOffset: Double {
        get { transitMapCenterOffset.north }
        set { setTransitMapCenterOffset(east: transitMapCenterOffset.east, north: newValue) }
    }

    func applyTransitUpdate(_ update: TransitRuntimeUpdate) async {
        guard update.activationGeneration == transitActivationGeneration else { return }
        semanticFramesByExperience[.transit] = update.experienceFrame
        await experienceCoordinator.reportRuntimeUpdate(
            id: .transit,
            generation: update.activationGeneration,
            successfulGeneration: update.successfulActivationGeneration,
            health: update.health,
        )

        let generation = update.activationGeneration
        let awaitsPreparation = await experienceCoordinator.isAwaitingPreparation(
            id: .transit,
            generation: generation,
        )
        if update.successfulActivationGeneration == generation, awaitsPreparation {
            do {
                let output = try await projectedOutput(
                    for: update.experienceFrame,
                    generatedAt: dateProvider.now(),
                )
                guard transitActivationGeneration == generation,
                      semanticFramesByExperience[.transit] == update.experienceFrame,
                      await experienceCoordinator.isAwaitingPreparation(
                          id: .transit,
                          generation: generation,
                      )
                else { return }
                preparedOutputsByExperience[.transit] = PreparedProjectionExperience(
                    experienceID: .transit,
                    activationGeneration: generation,
                    semanticFrame: update.experienceFrame,
                    output: output,
                )
                let accepted = await experienceCoordinator.reportRuntimePrepared(
                    id: .transit,
                    generation: generation,
                )
                if accepted == false,
                   preparedOutputsByExperience[.transit]?.activationGeneration == generation
                {
                    preparedOutputsByExperience.removeValue(forKey: .transit)
                }
            } catch is CancellationError {
                return
            } catch {
                await experienceCoordinator.reportRuntimeUpdate(
                    id: .transit,
                    generation: generation,
                    successfulGeneration: nil,
                    health: .failed(.decoding),
                )
                return
            }
        }

        guard activeExperienceID == .transit else { return }
        let previousHadContent = currentExperienceFrame.layers.isEmpty == false
        currentExperienceFrame = update.experienceFrame
        currentLayerFrame = update.experienceFrame.layers.first {
            $0.layerID == .transitVehicles
        } ?? update.experienceFrame.layers.first { $0.layerID == .transitNetwork }
        experienceHealth[.transit] = update.health
        if currentLayerFrame != nil {
            restartRenderer()
        } else if previousHadContent || update.health.visibleContentCount == 0 {
            await clearProjectionState(restartsGeography: true)
            experienceHealth[.transit] = update.health
        }
    }

    /// Downloads the current MTA schedule and verifies at least one realtime partition.
    public func configureNewYorkTransit() async -> Bool {
        let previousConfiguration = transitConfiguration
        let previousPlaylist = projectionPlaylist
        do {
            try await transitRuntime.validateConnection()
            try Task.checkCancellation()
            let dwell = ProjectionDwellDuration.defaultValue
            var entries = projectionPlaylist.entries.filter { $0.experienceID != .transit }
            entries.append(ProjectionPlaylistEntry(experienceID: .transit, dwellDuration: dwell))
            let configuredPlaylist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: entries.count > 1,
                selectedExperienceID: activeExperienceID ?? .airAndSpace,
                configuredExperienceIDs: [.airAndSpace, .transit],
                catalog: .standard,
            )
            transitConfiguration = .configured(cityID: .newYorkCity)
            projectionPlaylist = configuredPlaylist
            try await savePreferencesImmediately()
            settingsFailure = nil
            scheduleDemandReconciliation()
            return true
        } catch is CancellationError {
            transitConfiguration = previousConfiguration
            projectionPlaylist = previousPlaylist
            return false
        } catch {
            transitConfiguration = previousConfiguration
            projectionPlaylist = previousPlaylist
            settingsFailure = error.localizedDescription
            return false
        }
    }

    public func removeTransit() async {
        let previousConfiguration = transitConfiguration
        let previousPlaylist = projectionPlaylist
        do {
            let entries = projectionPlaylist.entries.filter { $0.experienceID != .transit }
            let airAndSpacePlaylist = try ProjectionPlaylist(
                entries: entries,
                automaticRotationEnabled: false,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
            transitConfiguration = .unconfigured
            projectionPlaylist = airAndSpacePlaylist
            try await savePreferencesImmediately()
            settingsFailure = nil
            await transitRuntime.deactivate(reporting: .idle)
            scheduleDemandReconciliation()
        } catch {
            transitConfiguration = previousConfiguration
            projectionPlaylist = previousPlaylist
            settingsFailure = error.localizedDescription
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

    private func setTransitMapCenterOffset(east: Double, north: Double) {
        do {
            let boundedEast = min(max(east, -50), 50)
            let boundedNorth = min(max(north, -50), 50)
            let distance = try NauticalMiles(value: hypot(boundedEast, boundedNorth))
            transitMapCenter = try ProjectionEngine().destination(
                from: TransitPreferences.defaultValue.mapCenter,
                bearing: Bearing(degrees: atan2(boundedEast, boundedNorth) * 180 / .pi),
                distance: distance,
            )
        } catch {
            settingsFailure = error.localizedDescription
        }
    }
}
