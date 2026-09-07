import SFSafeSymbols
import SwiftUI

/// A complete developer-mode application surface for browsing and deleting an
/// app's configured files, defaults, and SwiftData records.
public struct InspectorView: View {
    private enum Destination: Hashable {
        case files(InspectorConfiguration.FileContainer.ID)
        case defaults(InspectorConfiguration.DefaultsDomain.ID)
        case swiftData(InspectorConfiguration.SwiftDataSource.ID)
    }

    @State private var model: InspectorModel
    @State private var modeController: InspectorModeController
    @State private var selection: Destination?

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
        Group {
            if model.preparationState == .ready {
                inspector
            } else {
                ProgressView("Preparing Inspector")
                    .task { await model.prepare() }
            }
        }
    }

    private var inspector: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Files") {
                    ForEach(model.configuration.fileContainers) { container in
                        NavigationLink(value: Destination.files(container.id)) {
                            Label(container.title, systemSymbol: .folder)
                        }
                    }
                }

                Section("User Defaults") {
                    ForEach(model.configuration.defaultsDomains) { domain in
                        NavigationLink(value: Destination.defaults(domain.id)) {
                            Label(domain.title, systemSymbol: .sliderHorizontal3)
                        }
                    }
                }

                Section("SwiftData") {
                    ForEach(model.visibleSwiftDataSources) { source in
                        NavigationLink(value: Destination.swiftData(source.id)) {
                            Label(source.title, systemSymbol: .cylinderSplit1x2)
                        }
                    }
                }

                Section {
                    if let error = modeController.pendingStoreErasureError {
                        Label(error, systemSymbol: .exclamationmarkTriangleFill)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if modeController.nextLaunch == .inspector {
                        Button(
                            "Use Regular App on Next Launch",
                            systemSymbol: .arrowUturnForward,
                        ) {
                            modeController.useRegularApplicationOnNextLaunch()
                        }
                    } else {
                        Label(
                            "Regular app selected",
                            systemSymbol: .checkmarkCircleFill,
                        )
                        .foregroundStyle(.green)

                        Button(
                            "Keep Inspector on Next Launch",
                            systemSymbol: .wrenchAndScrewdriver,
                        ) {
                            modeController.enterInspectorOnNextLaunch()
                        }
                    }
                } header: {
                    Text("Next Launch")
                } footer: {
                    Text("Close and reopen the app to use the selected runtime.")
                }
            }
            .navigationTitle(model.configuration.title)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .onChange(of: model.removedSwiftDataSourceIDs) { _, removedSourceIDs in
            guard case let .swiftData(id) = selection,
                  removedSourceIDs.contains(id)
            else {
                return
            }
            selection = nil
        }
    }

    @ViewBuilder
    private var detail: some View {
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
            case nil:
                ContentUnavailableView(
                    "Inspector",
                    systemSymbol: .wrenchAndScrewdriver,
                    description: Text("Choose a data source from the sidebar."),
                )
        }
    }
}
