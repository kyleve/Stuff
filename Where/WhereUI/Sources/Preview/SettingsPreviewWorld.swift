#if DEBUG
    import InstallerKit
    import PeriscopeCore
    import WhereCore

    /// A synchronous Settings fixture whose models share one in-memory world.
    /// Preloaded report details provide static artwork without an async demo launch.
    @MainActor
    struct SettingsPreviewWorld {
        enum RecordingWarning {
            case absent
            case presented
        }

        let model: WhereModel
        let session: WhereSession
        let report: YearReportModel
        let backup: BackupModel
        let recordingWarning: RecordingConfigurationWarningModel

        init(theme: WhereTheme, recordingWarning: RecordingWarning) {
            let preferences = PreviewSupport.previewPreferences()
            preferences.hasOnboarded = true
            preferences.theme = theme
            switch recordingWarning {
                case .absent:
                    break
                case .presented:
                    var registration = preferences.recordingConfigurationWarningRegistration
                    registration.register(isWarningConditionActive: true)
                    preferences.recordingConfigurationWarningRegistration = registration
            }

            let services = PreviewSupport.previewServices()
            let details = PreviewSupport.sampleYearReportDetails()
            let model = WhereModel(
                services: services,
                details: details,
                selectedYear: PreviewSupport.year,
                preferences: preferences,
                logSystem: Periscope(configuration: Periscope.Configuration(), sinks: []),
                now: { PreviewSupport.referenceNow },
            )
            guard let session = model.session else {
                preconditionFailure("A ready Settings preview model must provide its session")
            }
            self.model = model
            self.session = session
            report = YearReportModel(
                services: session.services,
                details: details,
                selectedYear: PreviewSupport.year,
                preferences: session.preferences,
                now: session.now,
            )
            report.forecasts.setPlanning(PlanningSnapshot(stays: [], homeRegion: nil))
            backup = BackupModel(services: session.services)
            self.recordingWarning = RecordingConfigurationWarningModel(
                preferences: session.preferences,
            )
        }

        /// Supplies the complete app environment, with explicit fixture integrations.
        func environment(
            updates: UpdateModel?,
            developer: WhereEnvironment.Developer?,
        ) -> WhereEnvironment {
            .app(.init(
                model: model,
                updates: updates,
                developer: developer ?? .init(
                    inspector: nil,
                    launchController: nil,
                    cardDesigner: nil,
                ),
            ))
        }
    }
#endif
