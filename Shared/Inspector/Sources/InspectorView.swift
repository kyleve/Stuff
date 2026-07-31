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
        _model = State(initialValue: InspectorModel(configuration: configuration))
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
                            Label(container.title, systemImage: "folder")
                        }
                    }
                }

                Section("User Defaults") {
                    ForEach(model.configuration.defaultsDomains) { domain in
                        NavigationLink(value: Destination.defaults(domain.id)) {
                            Label(domain.title, systemImage: "slider.horizontal.3")
                        }
                    }
                }

                Section("SwiftData") {
                    ForEach(model.configuration.swiftDataSources) { source in
                        NavigationLink(value: Destination.swiftData(source.id)) {
                            Label(source.title, systemImage: "cylinder.split.1x2")
                        }
                    }
                }

                Section {
                    if modeController.nextLaunch == .inspector {
                        Button(
                            "Use Regular App on Next Launch",
                            systemImage: "arrow.uturn.forward",
                        ) {
                            modeController.useRegularApplicationOnNextLaunch()
                        }
                    } else {
                        Label(
                            "Regular app selected",
                            systemImage: "checkmark.circle.fill",
                        )
                        .foregroundStyle(.green)

                        Button(
                            "Keep Inspector on Next Launch",
                            systemImage: "wrench.and.screwdriver",
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
                    systemImage: "wrench.and.screwdriver",
                    description: Text("Choose a data source from the sidebar."),
                )
        }
    }
}
