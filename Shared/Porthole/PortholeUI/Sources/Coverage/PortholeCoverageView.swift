import PortholeCore
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// Catalog navigation keeps inactive and unsupported declarations beside actual binding coverage.
struct PortholeCoverageView: View {
    @State private var model: PortholeCoverageModel
    private let moduleSummary: PortholeCoverageModuleSummary?
    private let capabilities: [PortholeCapability]
    private let objects: [PortholeObjectReference]
    private let navigation: PortholeEvidenceNavigation
    @Environment(\.portholeStylesheet) private var stylesheet

    init(
        scope: PortholeScopeToken,
        module: PortholeCoverageModuleSummary?,
        capabilities: [PortholeCapability],
        objects: [PortholeObjectReference],
        navigation: PortholeEvidenceNavigation,
    ) {
        self.init(
            model: .init(scope: scope, module: module?.module, execute: navigation.execute),
            module: module,
            capabilities: capabilities,
            objects: objects,
            navigation: navigation,
        )
    }

    init(
        model: PortholeCoverageModel,
        module: PortholeCoverageModuleSummary?,
        capabilities: [PortholeCapability],
        objects: [PortholeObjectReference],
        navigation: PortholeEvidenceNavigation,
    ) {
        _model = State(initialValue: model)
        moduleSummary = module
        self.capabilities = capabilities
        self.objects = objects
        self.navigation = navigation
    }

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Text(
                    "Coverage includes declarations that are inactive or cannot be called. Search names, signatures, conditions, or unsupported reasons.",
                )
                .foregroundStyle(.secondary)
            }
            if let moduleSummary {
                Section("Installed module") {
                    LabeledContent("Configuration", value: moduleSummary.build.configuration)
                    Text(moduleSummary.build.toolchain).font(stylesheet.code.font)
                        .textSelection(.enabled)
                    Text(
                        "\(moduleSummary.sourceFileCount) source files · \(moduleSummary.counts.total) declarations",
                    )
                    Text(
                        "\(moduleSummary.counts.callable) callable · \(moduleSummary.counts.inspectableSource) inspectable source · \(moduleSummary.counts.unsupported) unsupported",
                    )
                    Text(
                        "\(moduleSummary.counts.inactive) inactive · \(moduleSummary.counts.sourceOnly) source only · \(moduleSummary.counts.excluded) excluded",
                    )
                }
            }
            switch model.state {
                case .idle, .loading: ProgressView("Reading API coverage…")
                case let .failed(message):
                    Section("Coverage unavailable") {
                        Label(message, systemSymbol: .exclamationmarkTriangle)
                        Button("Retry") { Task { await model.load() } }
                    }
                case let .loaded(page):
                    switch page {
                        case let .modules(page):
                            Section("Exported modules") {
                                ForEach(page.items, id: \.module) { module in
                                    NavigationLink {
                                        PortholeCoverageView(
                                            scope: page.scope,
                                            module: module,
                                            capabilities: capabilities,
                                            objects: objects,
                                            navigation: navigation,
                                        )
                                    } label: {
                                        VStack(
                                            alignment: .leading,
                                            spacing: stylesheet.row.spacing,
                                        ) {
                                            Text(module.module.rawValue).font(.headline)
                                            Text(
                                                "\(module.counts.total) declarations · \(module.counts.callable) callable · \(module.counts.inactive) inactive",
                                            )
                                            Text(module.build.configuration).font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        case let .declarations(page):
                            Section("Declarations") {
                                ForEach(page.items, id: \.declaration.id) { entry in
                                    NavigationLink {
                                        PortholeCoverageDeclarationView(
                                            entry: entry,
                                            scope: page.scope,
                                            capabilities: capabilities,
                                            objects: objects,
                                            navigation: navigation,
                                        )
                                    } label: {
                                        VStack(
                                            alignment: .leading,
                                            spacing: stylesheet.row.spacing,
                                        ) {
                                            Text(entry.declaration.name).font(.headline)
                                            Text(entry.statusTitle)
                                            Text(entry.plannedSupportTitle).font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(entry.declaration.signature)
                                                .font(stylesheet.code.font).fixedSize(
                                                    horizontal: false,
                                                    vertical: true,
                                                )
                                            Text(entry.statusReason).font(.caption).fixedSize(
                                                horizontal: false,
                                                vertical: true,
                                            )
                                            if let reason = entry.plannedSupportReason,
                                               reason != entry
                                               .statusReason
                                            {
                                                Text(reason).font(.caption).fixedSize(
                                                    horizontal: false,
                                                    vertical: true,
                                                )
                                            }
                                            Text(entry.module.rawValue).font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                    }
                    pagination(page)
            }
        }
        .navigationTitle(model.module?.rawValue ?? "API coverage")
        .searchable(text: $model.search, prompt: "Declarations, conditions, or reasons")
        .task(id: model.request) { await model.loadIfNeeded() }
        .onDisappear { model.cancel() }
    }

    private func pagination(_ page: PortholeCoverageModel.Page) -> some View {
        Section {
            if page.count == 0 {
                Text("No matching declarations or modules.").foregroundStyle(.secondary)
            } else {
                Text("\(model.offset + 1)–\(model.offset + page.count) of \(page.total)")
                    .foregroundStyle(.secondary)
            }
            if model.offset > 0 { Button("Previous page") { model.previousPage() } }
            if page.count > 0, model.offset < page.total, page.count < page.total - model.offset {
                Button("Next page") { model.nextPage() }
            }
        }
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeCoverageView.snapshotPreviews }

    extension PortholeCoverageView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let configurations = SnapshotConfiguration.combinations(
                devices: [.iPhoneFullContent],
                colorSchemes: [.light],
                dynamicTypes: [.large, .accessibility5],
            ) + SnapshotConfiguration.combinations(
                devices: [.iPhoneFullContent],
                snapshotTypes: [.accessibility],
            )
            let modules = PortholeCoverageSnapshotFixture(module: nil)
            let declarations =
                PortholeCoverageSnapshotFixture(module: PortholeCoverageSnapshotServices.modules[0])
            SnapshotCase(
                name: "Modules including zero active",
                configurations: configurations,
                onReadyToMeasure: { await modules.prepare() },
                onReadyToSnapshot: { await modules.prepare() },
            ) {
                NavigationStack { modules.content }.portholeBroadwayRoot()
            }
            SnapshotCase(
                name: "Actual and planned coverage",
                configurations: configurations,
                onReadyToMeasure: { await declarations.prepare() },
                onReadyToSnapshot: { await declarations.prepare() },
            ) {
                NavigationStack { declarations.content }.portholeBroadwayRoot()
            }
        }
    }
#endif
