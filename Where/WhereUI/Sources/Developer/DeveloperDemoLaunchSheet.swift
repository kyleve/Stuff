#if DEBUG
    import Foundation
    import Inspector
    import Observation
    import SnapshotKit
    import SwiftUI
    import WhereCore

    @MainActor
    @Observable
    private final class DeveloperDemoLaunchSheetModel {
        var missingDays: Bool
        var borderDrift: Bool
        var abruptChange: Bool
        var flightDay: Bool

        init(configuration: DemoDataBuilder.Configuration) {
            missingDays = configuration.issueCategories.contains(.missingDays)
            borderDrift = configuration.issueCategories.contains(.borderDrift)
            abruptChange = configuration.issueCategories.contains(.abruptChange)
            flightDay = configuration.issueCategories.contains(.flightDay)
        }

        var configuration: DemoDataBuilder.Configuration {
            var categories: Set<DataIssueCategory> = []
            if missingDays { categories.insert(.missingDays) }
            if borderDrift { categories.insert(.borderDrift) }
            if abruptChange { categories.insert(.abruptChange) }
            if flightDay { categories.insert(.flightDay) }
            return DemoDataBuilder.Configuration(issueCategories: categories)
        }
    }

    /// Configures which Resolve workflows appear in the one-shot launch demo.
    struct DeveloperDemoLaunchSheet: View {
        let controller: WhereDeveloperLaunchController
        @State private var model: DeveloperDemoLaunchSheetModel
        @Environment(\.dismiss) private var dismiss

        init(controller: WhereDeveloperLaunchController) {
            self.controller = controller
            let configuration = if case let .demo(configuration) = controller.nextLaunch {
                configuration
            } else {
                DemoDataBuilder.Configuration.allIssues
            }
            _model = State(initialValue: DeveloperDemoLaunchSheetModel(
                configuration: configuration,
            ))
        }

        var body: some View {
            @Bindable var model = model
            NavigationStack {
                Form {
                    Section {
                        Toggle(
                            WhereFormat.resolutionSectionHeader(.missingDays),
                            isOn: $model.missingDays,
                        )
                        Toggle(
                            WhereFormat.resolutionSectionHeader(.borderDrift),
                            isOn: $model.borderDrift,
                        )
                        Toggle(
                            WhereFormat.resolutionSectionHeader(.abruptChange),
                            isOn: $model.abruptChange,
                        )
                        Toggle(
                            WhereFormat.resolutionSectionHeader(.flightDay),
                            isOn: $model.flightDay,
                        )
                    } header: {
                        Text(String(localized: .developerDemoIssuesHeader))
                    } footer: {
                        Text(String(localized: .developerDemoIssuesFooter))
                    }

                    if case .demo = controller.nextLaunch {
                        Section {
                            Button(
                                String(localized: .developerDemoCancelScheduled),
                                role: .destructive,
                            ) {
                                controller.useRegularApplicationOnNextLaunch()
                                dismiss()
                            }
                        }
                    }
                }
                .navigationTitle(String(localized: .developerDemoSheetTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: .commonCancel)) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .developerDemoSchedule)) {
                            controller.scheduleDemo(model.configuration)
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private struct DeveloperDemoLaunchSheetPreview: View {
        @State private var controller: WhereDeveloperLaunchController

        init() {
            let suiteName = "where.developer-demo-sheet.preview"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("Unable to open demo sheet preview defaults")
            }
            defaults.removePersistentDomain(forName: suiteName)
            _controller = State(initialValue: WhereDeveloperLaunchController(
                userDefaults: defaults,
                inspectorModeController: InspectorModeController(userDefaults: defaults),
            ))
        }

        var body: some View {
            DeveloperDemoLaunchSheet(controller: controller)
        }
    }

    extension DeveloperDemoLaunchSheet: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(name: "AllIssues", configurations: .phoneLightDark) {
                DeveloperDemoLaunchSheetPreview()
            }
        }
    }

    #Preview {
        DeveloperDemoLaunchSheet.snapshotPreviews
    }
#endif
