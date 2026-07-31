#if targetEnvironment(macCatalyst)
    import Observation
    import ServiceManagement

    /// Mirrors the embedded login item's real Service Management state and
    /// applies the user's enable/disable request.
    @MainActor
    @Observable
    final class MenuBarSettingsModel {
        /// The states Settings needs to distinguish without exposing
        /// `SMAppService` to the view.
        enum Status: Equatable {
            case disabled
            case enabled
            case requiresApproval
            case unavailable

            var isRegistered: Bool {
                switch self {
                    case .enabled, .requiresApproval:
                        true
                    case .disabled, .unavailable:
                        false
                }
            }
        }

        private let service = SMAppService.loginItem(identifier: "com.stuff.where.menubar")

        private(set) var status: Status
        private(set) var isApplying = false
        private(set) var errorMessage: String?
        var isEnabled: Bool

        var isShowingError: Bool {
            get { errorMessage != nil }
            set {
                if !newValue {
                    errorMessage = nil
                }
            }
        }

        init() {
            let status = Self.status(for: service.status)
            self.status = status
            isEnabled = status.isRegistered
        }

        func refresh() {
            status = Self.status(for: service.status)
            isEnabled = status.isRegistered
        }

        func applyRequestedState() async {
            let serviceStatus = Self.status(for: service.status)
            guard isEnabled != serviceStatus.isRegistered else {
                status = serviceStatus
                return
            }

            isApplying = true
            defer {
                isApplying = false
                refresh()
            }

            do {
                if isEnabled {
                    try service.register()
                } else {
                    try await service.unregister()
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        func openLoginItemsSettings() {
            SMAppService.openSystemSettingsLoginItems()
        }

        private static func status(for status: SMAppService.Status) -> Status {
            switch status {
                case .notRegistered:
                    .disabled
                case .enabled:
                    .enabled
                case .requiresApproval:
                    .requiresApproval
                case .notFound:
                    .unavailable
                @unknown default:
                    .unavailable
            }
        }
    }
#endif
