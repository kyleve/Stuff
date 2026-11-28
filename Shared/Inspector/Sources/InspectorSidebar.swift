import SFSafeSymbols
import SwiftUI

struct InspectorSidebar: View {
    let model: InspectorModel
    let modeController: InspectorModeController
    @Binding var selection: InspectorDestination?

    var body: some View {
        List(selection: $selection) {
            InspectorSourceSection(
                title: "Files",
                symbol: .folder,
                sources: model.configuration.fileContainers,
                name: \.title,
                destination: InspectorDestination.files,
            )
            InspectorSourceSection(
                title: "User Defaults",
                symbol: .sliderHorizontal3,
                sources: model.configuration.defaultsDomains,
                name: \.title,
                destination: InspectorDestination.defaults,
            )
            InspectorSourceSection(
                title: "SwiftData",
                symbol: .cylinderSplit1x2,
                sources: model.visibleSwiftDataSources,
                name: \.title,
                destination: InspectorDestination.swiftData,
            )
            InspectorNextLaunchSection(modeController: modeController)
        }
        .navigationTitle(model.configuration.title)
    }
}

private struct InspectorSourceSection<Source: Identifiable>: View {
    let title: LocalizedStringKey
    let symbol: SFSymbol
    let sources: [Source]
    let name: KeyPath<Source, String>
    let destination: (Source.ID) -> InspectorDestination

    var body: some View {
        Section(title) {
            ForEach(sources) { source in
                NavigationLink(value: destination(source.id)) {
                    Label(source[keyPath: name], systemSymbol: symbol)
                }
            }
        }
    }
}

private struct InspectorNextLaunchSection: View {
    let modeController: InspectorModeController

    var body: some View {
        Section {
            if let error = modeController.pendingStoreErasureError {
                Label(error, systemSymbol: .exclamationmarkTriangleFill)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if modeController.nextLaunch != .inspector {
                Label("Regular app selected", systemSymbol: .checkmarkCircleFill)
                    .foregroundStyle(.green)
            }
            InspectorLaunchButton(modeController: modeController)
        } header: {
            Text("Next Launch")
        } footer: {
            Text("Close and reopen the app to use the selected runtime.")
        }
    }
}

private struct InspectorLaunchButton: View {
    let modeController: InspectorModeController

    var body: some View {
        if modeController.nextLaunch == .inspector {
            Button(
                "Use Regular App on Next Launch",
                systemSymbol: .arrowUturnForward,
                action: modeController.useRegularApplicationOnNextLaunch,
            )
        } else {
            Button(
                "Keep Inspector on Next Launch",
                systemSymbol: .wrenchAndScrewdriver,
                action: modeController.enterInspectorOnNextLaunch,
            )
        }
    }
}

#if DEBUG
    #Preview {
        InspectorView(
            configuration: InspectorPreviewData.configuration,
            modeController: InspectorPreviewData.modeController,
        )
    }
#endif
