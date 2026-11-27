#if DEBUG
    import Observation

    /// Owns the confirmation for one Privacy & Diagnostics presentation.
    @MainActor
    @Observable
    final class DiagnosticPersonalDataConfirmation {
        private let reporting: DiagnosticReportingSettingsModel
        private var requestedRevision: UInt64?

        init(reporting: DiagnosticReportingSettingsModel) {
            self.reporting = reporting
        }

        var includesPersonalData: Bool {
            get { reporting.includesPersonalData }
            set {
                if newValue {
                    guard canRequestGrant else { return }
                    requestedRevision = reporting.remoteLoggingRevision
                } else {
                    requestedRevision = nil
                    reporting.disablePersonalData()
                }
            }
        }

        var pendingRevision: UInt64? {
            guard canRequestGrant, requestedRevision == reporting.remoteLoggingRevision
            else { return nil }
            return requestedRevision
        }

        var isPresented: Bool {
            get { pendingRevision != nil }
            set { if !newValue { requestedRevision = nil } }
        }

        private var canRequestGrant: Bool {
            reporting.selectedRemoteLevel != nil && !reporting.includesPersonalData
        }

        func confirm(revision: UInt64) {
            requestedRevision = nil
            guard canRequestGrant, reporting.remoteLoggingRevision == revision else { return }
            reporting.enablePersonalData()
        }
    }
#endif
