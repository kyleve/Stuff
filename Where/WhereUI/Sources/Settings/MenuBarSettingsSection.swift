#if targetEnvironment(macCatalyst)
    import SwiftUI

    /// Mac-only control for the native, embedded menu-bar login item.
    struct MenuBarSettingsSection: View {
        @Bindable var model: MenuBarSettingsModel
        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            Section {
                Toggle(
                    String(localized: .settingsMenuBarEnabled),
                    isOn: $model.isEnabled,
                )
                .disabled(model.isApplying || model.status == .unavailable)

                if model.status == .requiresApproval {
                    Button(
                        String(localized: .settingsMenuBarOpenLoginItems),
                        action: model.openLoginItemsSettings,
                    )
                }
            } header: {
                Text(String(localized: .settingsMenuBarHeader))
            } footer: {
                Text(footer)
            }
            .task(id: model.isEnabled) {
                await model.applyRequestedState()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.refresh()
                }
            }
            .alert(
                String(localized: .settingsMenuBarErrorTitle),
                isPresented: $model.isShowingError,
                presenting: model.errorMessage,
            ) { _ in
            } message: { message in
                Text(message)
            }
        }

        private var footer: String {
            switch model.status {
                case .disabled, .enabled:
                    String(localized: .settingsMenuBarFooter)
                case .requiresApproval:
                    String(localized: .settingsMenuBarApprovalFooter)
                case .unavailable:
                    String(localized: .settingsMenuBarUnavailableFooter)
            }
        }
    }

    #if DEBUG
        #Preview {
            Form {
                MenuBarSettingsSection(model: MenuBarSettingsModel())
            }
        }
    #endif
#endif
