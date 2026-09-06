import Testing
@_spi(Testing) @testable import ThrowCore

struct ProjectionPlaylistTests {
    private let airEntry = ProjectionPlaylistEntry(
        runnableExperienceID: .airAndSpace,
        dwellDuration: .defaultValue,
    )

    @Test(arguments: [30, 120, 1800])
    func acceptsDwellBoundsAndSteps(seconds: Int) throws {
        #expect(try ProjectionDwellDuration(seconds: seconds).seconds == seconds)
    }

    @Test(arguments: [0, 29, 31, 1801])
    func rejectsInvalidDwellDurations(seconds: Int) {
        #expect(throws: ProjectionPlaylistError.invalidDwellDuration) {
            try ProjectionDwellDuration(seconds: seconds)
        }
    }

    @Test func oneConfiguredExperienceLeavesRotationDormant() throws {
        let playlist = try ProjectionPlaylist(
            entries: [airEntry],
            automaticRotationEnabled: true,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace],
            catalog: .standard,
        )

        #expect(playlist.rotatesAutomatically == false)
        #expect(playlist.experience(after: .airAndSpace) == nil)
    }

    @Test func duplicateEntriesAreRejected() {
        #expect(throws: ProjectionPlaylistError.duplicateExperience) {
            try ProjectionPlaylist(
                entries: [airEntry, airEntry],
                automaticRotationEnabled: true,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        }
    }

    @Test func plannedEntriesAreRejected() {
        let transit = ProjectionPlaylistEntry(
            runnableExperienceID: .testing(.transit),
            dwellDuration: .defaultValue,
        )
        #expect(throws: ProjectionPlaylistError.unavailableExperience) {
            try ProjectionPlaylist(
                entries: [transit],
                automaticRotationEnabled: false,
                selectedExperienceID: .testing(.transit),
                configuredExperienceIDs: [.testing(.transit)],
                catalog: .standard,
            )
        }
    }

    @Test func enabledButUnconfiguredEntryIsRejected() throws {
        let entry = ProjectionPlaylistEntry(
            runnableExperienceID: .airAndSpace,
            dwellDuration: .defaultValue,
        )

        #expect(throws: ProjectionPlaylistError.unconfiguredExperience) {
            try ProjectionPlaylist(
                entries: [entry],
                automaticRotationEnabled: false,
                selectedExperienceID: .airAndSpace,
                configuredExperienceIDs: [],
                catalog: .standard,
            )
        }
    }

    @Test func configuringSecondExperienceAppendsDefaultDwellAndEnablesRotation() throws {
        let catalog = enabledTwoExperienceCatalog()
        let first = try ProjectionPlaylist(
            entries: [ProjectionPlaylistEntry(
                runnableExperienceID: .airAndSpace,
                dwellDuration: .defaultValue,
            )],
            automaticRotationEnabled: false,
            selectedExperienceID: .airAndSpace,
            configuredExperienceIDs: [.airAndSpace],
            catalog: catalog,
        )

        let playlist = try first.addingConfiguredExperience(
            .testing(.transit),
            dwellDuration: .defaultValue,
            configuredExperienceIDs: [.airAndSpace, .testing(.transit)],
            catalog: catalog,
        )

        #expect(playlist.entries.map(\.experienceID) == [.airAndSpace, .transit])
        #expect(
            playlist.entry(for: .testing(.transit))?.dwellDuration == .defaultValue,
        )
        #expect(playlist.automaticRotationEnabled)
        #expect(playlist.rotatesAutomatically)
    }

    @Test func invalidSelectionIsRejected() {
        #expect(throws: ProjectionPlaylistError.invalidSelection) {
            try ProjectionPlaylist(
                entries: [airEntry],
                automaticRotationEnabled: false,
                selectedExperienceID: nil,
                configuredExperienceIDs: [.airAndSpace],
                catalog: .standard,
            )
        }
    }

    private func enabledTwoExperienceCatalog() -> ProjectionExperienceCatalog {
        ProjectionExperienceCatalog(
            testingDescriptors: [
                ProjectionExperienceDescriptor(
                    testingAvailability: .runnable(.airAndSpace),
                    supportedModes: [.map, .trueSky],
                    layerIDs: [.geography, .flights],
                    visibleContentKind: .aircraft,
                    zOrder: 0,
                ),
                ProjectionExperienceDescriptor(
                    testingAvailability: .runnable(.testing(.transit)),
                    supportedModes: [.map],
                    layerIDs: [.geography, .transitNetwork, .transitVehicles],
                    visibleContentKind: .vehicles,
                    zOrder: 10,
                ),
            ],
            layerCatalog: .standard,
        )
    }
}
