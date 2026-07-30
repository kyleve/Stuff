#if DEBUG
    import Foundation
    import Inspector
    import PeriscopeCore
    import PeriscopeTools
    import RegionKit
    import SnapshotKit
    import SwiftUI
    import WhereCore

    /// The developer tools surface — the Periscope log viewer + open-spans
    /// monitor, the "Log View Mode" toggle, the next-launch Inspector control,
    /// and the region map.
    ///
    /// Owns its own `NavigationStack` so the generic viewers (which expect an
    /// ambient stack) work wherever it's hosted. It reads the app `WhereModel`
    /// (for the process-global log store) and `InspectorModeController` as
    /// optionals because the developer overlay is reachable in fixtures that
    /// inject only one of them — dependent rows simply hide.
    ///
    /// Compiled out of release entirely (`#if DEBUG`).
    struct DeveloperToolsView: View {
        @Environment(WhereModel.self) private var model: WhereModel?
        @Environment(InspectorModeController.self) private var modeController:
            InspectorModeController?
        @Environment(\.periscopeInspector) private var inspector

        /// Extra bottom scroll inset so the last rows clear the floating HUD's
        /// resize grip. Zero (the default) when hosted without the overlay chrome
        /// (previews, tests, full screen).
        var bottomContentInset: CGFloat = 0

        var body: some View {
            NavigationStack {
                List {
                    Section {
                        if let store = model?.logStore {
                            NavigationLink {
                                PeriscopeViewer(
                                    store: store,
                                    title: String(localized: .developerLogsTitle),
                                )
                            } label: {
                                Label(String(localized: .developerLogsLink), systemImage: "ladybug")
                            }
                        }

                        NavigationLink {
                            OpenSpansView(system: .shared)
                        } label: {
                            Label(String(localized: .developerOpenSpansLink), systemImage: "timer")
                        }

                        NavigationLink {
                            RegionMapView()
                        } label: {
                            Label(String(localized: .developerRegionMapLink), systemImage: "map")
                        }
                    } footer: {
                        Text(String(localized: .developerFooter))
                    }

                    if let inspector {
                        LogViewModeSection(inspector: inspector)
                    }

                    if let modeController {
                        InspectorBootSection(controller: modeController)
                    }
                }
                .navigationTitle(String(localized: .developerTitle))
                .navigationBarTitleDisplayMode(.inline)
                // Let the HUD's glass surface show through the list.
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, bottomContentInset, for: .scrollContent)
            }
        }
    }

    private struct InspectorBootSection: View {
        @Bindable var controller: InspectorModeController

        var body: some View {
            Section("Inspector") {
                if controller.nextLaunch == .inspector {
                    Label(
                        String(localized: .developerInspectorNextLaunchSelected),
                        systemImage: "checkmark.circle.fill",
                    )
                    .foregroundStyle(.green)

                    Button(
                        String(localized: .developerCancelInspectorNextLaunch),
                        systemImage: "xmark.circle",
                    ) {
                        controller.useRegularApplicationOnNextLaunch()
                    }
                } else {
                    Button(
                        String(localized: .developerEnterInspectorNextLaunch),
                        systemImage: "wrench.and.screwdriver",
                    ) {
                        controller.enterInspectorOnNextLaunch()
                    }
                }
            }
        }
    }

    /// The "Log View Mode" toggle: binds straight to the injected
    /// ``PeriscopeInspector`` (the source of truth is `Periscope.shared`'s
    /// inspect flag, which the inspector mirrors both ways), so flipping it
    /// reveals the inspect badges `debugLogInspectable(_:)` adds across the app.
    private struct LogViewModeSection: View {
        @Bindable var inspector: PeriscopeInspector

        var body: some View {
            Section {
                Toggle(String(localized: .developerLogViewMode), isOn: $inspector.isEnabled)
            } footer: {
                Text(String(localized: .developerLogViewModeFooter))
            }
        }
    }

    extension DeveloperToolsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "Default", configurations: .phoneLightDark) {
                DeveloperToolsView()
                    .environment(PreviewSupport.loadedModel())
                    .environment(PreviewSupport.loadedSession())
                    .environment(snapshotModeController as InspectorModeController?)
            }
        }

        private static var snapshotModeController: InspectorModeController {
            let suiteName = "where.developer-tools.snapshot.inspector"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open snapshot defaults")
            }
            defaults.removePersistentDomain(forName: suiteName)
            return InspectorModeController(userDefaults: defaults)
        }
    }

    #Preview {
        DeveloperToolsView.snapshotPreviews
    }
#endif
