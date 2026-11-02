#if DEBUG
    import Testing
    import WhereCore
    @testable import WhereUI

    @MainActor
    struct SettingsPreviewWorldTests {
        @Test func relatedModelsShareTheExistingSessionAndPreferenceOwner() {
            let world = SettingsPreviewWorld(theme: .alternate, recordingWarning: .presented)
            let other = SettingsPreviewWorld(theme: .standard, recordingWarning: .absent)

            #expect(world.session === world.model.session)
            #expect(world.report.preferences === world.model.preferences)
            #expect(world.report.preferences === world.session.preferences)
            #expect(world.report.services.journal === world.session.services.journal)
            #expect(world.model.theme == .alternate)
            #expect(world.report.preferences.theme == .alternate)

            world.report.showsRecordedLocationDots = false
            #expect(world.model.preferences.showsRecordedLocationDots == false)
            #expect(world.session.preferences.showsRecordedLocationDots == false)
            #expect(other.report.showsRecordedLocationDots)

            #expect(world.recordingWarning.isPresented)
            world.recordingWarning.dismiss()
            #expect(world.model.preferences.recordingConfigurationWarningRegistration
                .requiresWarning == false)
            #expect(other.recordingWarning.isPresented == false)
        }

        @Test func sessionWritesReportClearsAndBackupExportsUseTheSameStore() async throws {
            let world = SettingsPreviewWorld(theme: .standard, recordingWarning: .absent)
            let other = SettingsPreviewWorld(theme: .standard, recordingWarning: .absent)
            let day = CalendarDay(year: PreviewSupport.year, month: 6, day: 1)
            try await world.session.services.journal.addManualDay(
                date: day.startOfDay(in: world.report.calendar),
                regions: [.california],
                audit: nil,
            )

            let written = try await SettingsPreviewWorldTestSupport.exportArchive(
                using: world.backup,
            )
            #expect(written.manualDays.map(\.day) == [day])
            #expect(written.manualDays.first?.regions == [.california])
            let untouched = try await SettingsPreviewWorldTestSupport.exportArchive(
                using: other.backup,
            )
            #expect(untouched.manualDays.isEmpty)

            await world.report.clearSelectedYear()
            let cleared = try await SettingsPreviewWorldTestSupport.exportArchive(
                using: world.backup,
            )
            #expect(cleared.manualDays.isEmpty)
        }
    }
#endif
