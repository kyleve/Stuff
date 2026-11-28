#if DEBUG
    import SnapshotKit
    import SwiftUI
    import WhereCore

    struct DeveloperDemoIssuesSection: View {
        @Bindable var model: DeveloperDemoLaunchSheetModel

        var body: some View {
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
        }
    }

    #Preview { DeveloperDemoLaunchSheet.snapshotPreviews }
#endif
