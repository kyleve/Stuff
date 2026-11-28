import SFSafeSymbols
import SwiftUI

struct InspectorDetail: View {
    let model: InspectorModel
    let selection: InspectorDestination?

    var body: some View {
        switch selection {
            case let .files(id):
                if let container = model.configuration.fileContainers.first(where: { $0.id == id }),
                   let fileSystem = model.fileSystem
                {
                    InspectorFileBrowserView(container: container, fileSystem: fileSystem)
                }
            case let .defaults(id):
                if let domain = model.configuration.defaultsDomains.first(where: { $0.id == id }) {
                    InspectorDefaultsView(domain: domain)
                }
            case let .swiftData(id):
                InspectorSwiftDataDestination(model: model, id: id)
            case nil:
                ContentUnavailableView(
                    "Inspector",
                    systemSymbol: .wrenchAndScrewdriver,
                    description: Text("Choose a data source from the sidebar."),
                )
        }
    }
}

private struct InspectorSwiftDataDestination: View {
    let model: InspectorModel
    let id: InspectorConfiguration.SwiftDataSource.ID

    var body: some View {
        if let loaded = model.loadedSwiftDataSources[id] {
            InspectorSwiftDataView(model: loaded.model)
        } else if model.swiftDataFailures[id] != nil,
                  let source = model.configuration.swiftDataSources.first(where: {
                      $0.id == id
                  })
        {
            InspectorUnavailableSwiftDataView(
                source: source,
                model: model,
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
