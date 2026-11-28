import SFSafeSymbols
import SwiftUI

/// A complete developer-mode application surface for browsing and deleting an
/// app's configured files, defaults, and SwiftData records.
public struct InspectorView: View {
    @State private var model: InspectorModel
    @State private var modeController: InspectorModeController
    @State private var selection: InspectorDestination?

    public init(
        configuration: InspectorConfiguration,
        modeController: InspectorModeController,
    ) {
        _model = State(initialValue: InspectorModel(
            configuration: configuration,
            modeController: modeController,
        ))
        _modeController = State(initialValue: modeController)
    }

    public var body: some View {
        if model.preparationState == .ready {
            InspectorNavigation(model: model, modeController: modeController, selection: $selection)
        } else {
            ProgressView("Preparing Inspector")
                .task { await model.prepare() }
        }
    }
}

enum InspectorDestination: Hashable {
    case files(InspectorConfiguration.FileContainer.ID)
    case defaults(InspectorConfiguration.DefaultsDomain.ID)
    case swiftData(InspectorConfiguration.SwiftDataSource.ID)
}

private struct InspectorNavigation: View {
    let model: InspectorModel
    let modeController: InspectorModeController
    @Binding var selection: InspectorDestination?

    var body: some View {
        NavigationSplitView {
            InspectorSidebar(model: model, modeController: modeController, selection: $selection)
        } detail: {
            NavigationStack { InspectorDetail(model: model, selection: selection) }
        }
        .onChange(of: model.removedSwiftDataSourceIDs) { _, removedSourceIDs in
            guard case let .swiftData(id) = selection, removedSourceIDs.contains(id) else { return }
            selection = nil
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
