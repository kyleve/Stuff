#if DEBUG
    import Foundation
    import PeriscopeCore
    import WhereCore

    /// One unactivated, memory-only demo scope shared by every live Flyover frame.
    @MainActor
    final class WhereFlyoverWorld {
        let scope: WhereScope
        let model: WhereModel
        let session: WhereSession
        let report: YearReportModel
        let reminders: RemindersSettingsModel
        let backup: BackupModel

        private init(
            scope: WhereScope,
            model: WhereModel,
            session: WhereSession,
            report: YearReportModel,
            reminders: RemindersSettingsModel,
            backup: BackupModel,
        ) {
            self.scope = scope
            self.model = model
            self.session = session
            self.report = report
            self.reminders = reminders
            self.backup = backup
        }

        static func build() async throws -> WhereFlyoverWorld {
            let now: @Sendable () -> Date = { PreviewSupport.referenceNow }
            let logSystem = Periscope(
                configuration: Periscope.Configuration(),
                sinks: [],
            )
            let scope = try await WhereScope.demo(now: now, logSystem: logSystem)
            let session = WhereSession(scope: scope, now: now)
            await session.start()

            let model = WhereModel(
                services: scope.services,
                selectedYear: PreviewSupport.year,
                preferences: scope.preferences,
                logSystem: logSystem,
                now: now,
            )
            if let logStore = scope.logStore {
                model.attach(logStore: logStore)
            }

            let report = YearReportModel(
                services: scope.services,
                selectedYear: PreviewSupport.year,
                preferences: scope.preferences,
                now: now,
            )
            await report.activate()

            return WhereFlyoverWorld(
                scope: scope,
                model: model,
                session: session,
                report: report,
                reminders: RemindersSettingsModel(
                    services: scope.services,
                    preferences: scope.preferences,
                    now: now,
                ),
                backup: BackupModel(services: scope.services),
            )
        }

        static func preview() -> WhereFlyoverWorld {
            let services = PreviewSupport.previewServices()
            let preferences = PreviewSupport.previewPreferences()
            let logSystem = PreviewSupport.logSystem
            let now: @Sendable () -> Date = { PreviewSupport.referenceNow }
            let scope = WhereScope.fake(
                services: services,
                preferences: preferences,
                logSystem: logSystem,
            )
            let session = WhereSession(scope: scope, now: now)
            let model = WhereModel(
                services: services,
                details: PreviewSupport.sampleYearReportDetails(),
                selectedYear: PreviewSupport.year,
                preferences: preferences,
                logSystem: logSystem,
                now: now,
            )
            let report = YearReportModel(
                services: services,
                details: PreviewSupport.sampleYearReportDetails(),
                selectedYear: PreviewSupport.year,
                preferences: preferences,
                now: now,
            )
            return WhereFlyoverWorld(
                scope: scope,
                model: model,
                session: session,
                report: report,
                reminders: RemindersSettingsModel(
                    services: services,
                    preferences: preferences,
                    now: now,
                ),
                backup: BackupModel(services: services),
            )
        }
    }
#endif
