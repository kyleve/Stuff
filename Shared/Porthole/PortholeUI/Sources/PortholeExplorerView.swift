import PortholeRuntime
import SFSafeSymbols
import SwiftUI

struct PortholeExplorerView: View {
    @Bindable var controller: PortholePresentationController
    @Environment(\.portholeStylesheet) private var stylesheet

    var body: some View {
        List {
            if let origin = controller.origin {
                Section("Started from") {
                    switch origin {
                        case let .screen(context):
                            Label(context.title, systemSymbol: .viewfinder)
                            Text(context.capturedAt, format: .dateTime).font(.caption)
                                .foregroundStyle(.secondary)
                        case .application:
                            Label(controller.applicationTitle, systemSymbol: .app)
                    }
                    Text(origin.scope.id.rawValue).font(stylesheet.code.font)
                        .textSelection(.enabled)
                }
            }
            if !controller.breadcrumbs.isEmpty {
                Section("Context path") {
                    ScrollView(.horizontal) {
                        HStack(spacing: stylesheet.row.spacing) {
                            ForEach(controller.breadcrumbs) { context in
                                Button(context.title) { controller.navigate(to: context) }
                                if context.id != controller.breadcrumbs.last?.id {
                                    Image(systemSymbol: .chevronRight).accessibilityHidden(true)
                                }
                            }
                        }
                    }
                    if let context = controller
                        .selectedContext { PortholeValueView(value: context.values) }
                }
            }
            switch controller.loadState {
                case .idle, .loading: ProgressView("Loading this scope…")
                case let .failed(message):
                    Section("Scope unavailable") {
                        Label(message, systemSymbol: .exclamationmarkTriangle)
                        Text("The captured origin above remains available.")
                            .foregroundStyle(.secondary)
                        Button("Reload") { Task { await controller.refresh() } }
                    }
                case let .loaded(snapshot): loaded(snapshot)
            }
        }
        .navigationTitle("Explore")
        .searchable(text: $controller.search, prompt: "APIs, types, or modules")
        .refreshable { await controller.refresh() }
    }

    @ViewBuilder private func loaded(_ snapshot: PortholePresentationController
        .Snapshot) -> some View
    {
        if !snapshot.contexts.isEmpty {
            Section("Captured contexts") {
                ForEach(snapshot.contexts) { context in
                    Button { controller.navigate(to: context) } label: {
                        Label(context.title, systemSymbol: .point3ConnectedTrianglepathDotted)
                    }
                }
            }
        }
        if let context = controller.selectedContext {
            Section("Context relationships") {
                PortholeContextGraphView(
                    graph: .init(context: context, knownContexts: snapshot.contexts),
                    navigation: .init(controller: controller),
                )
            }
        }
        if !snapshot.objects.isEmpty {
            Section("Live object references") {
                ForEach(snapshot.objects, id: \.id) { object in
                    PortholeEvidenceLink(
                        reference: .object(object),
                        navigation: .init(controller: controller),
                    )
                }
            }
        }
        if let scope = controller.origin?.scope {
            Section("API coverage") {
                NavigationLink("All declarations and compilation coverage") {
                    PortholeCoverageView(
                        scope: scope,
                        module: nil,
                        capabilities: snapshot.capabilities,
                        objects: snapshot.objects,
                        navigation: .init(controller: controller),
                    )
                    .id(scope)
                }
            }
        }
        if controller.search.isEmpty {
            Section("Registered capabilities by module") {
                ForEach(modules(in: snapshot), id: \.self) { module in
                    NavigationLink(module.rawValue) {
                        PortholeCapabilityListView(
                            capabilities: snapshot.capabilities.filter { $0.module == module },
                            objects: snapshot.objects,
                            controller: controller,
                            title: module.rawValue,
                        )
                    }
                }
            }
        } else {
            Section("Matching capabilities") {
                ForEach(snapshot.capabilities.filter {
                    $0.matches(search: controller.search)
                }) { capability in
                    capabilityLink(capability, objects: snapshot.objects)
                }
            }
        }
    }

    private func modules(in snapshot: PortholePresentationController
        .Snapshot) -> [PortholeModuleID]
    {
        Array(Set(snapshot.capabilities.map(\.module))).sorted { $0.rawValue < $1.rawValue }
    }

    @ViewBuilder private func capabilityLink(
        _ capability: PortholeCapability,
        objects: [PortholeObjectReference],
    ) -> some View {
        if let scope = controller.origin?.scope {
            NavigationLink {
                PortholeInvocationView(
                    capability: capability,
                    objects: objects,
                    scope: scope,
                    controller: controller,
                )
            } label: { PortholeCapabilityLabel(capability: capability) }
        }
    }
}

struct PortholeCapabilityListView: View {
    let capabilities: [PortholeCapability]
    let objects: [PortholeObjectReference]
    let controller: PortholePresentationController
    let title: String
    @State private var search = ""

    var body: some View {
        List(capabilities
            .filter { $0.matches(search: search) })
        { capability in
            if let scope = controller.origin?.scope {
                NavigationLink {
                    PortholeInvocationView(
                        capability: capability,
                        objects: objects,
                        scope: scope,
                        controller: controller,
                    )
                } label: { PortholeCapabilityLabel(capability: capability) }
            }
        }
        .navigationTitle(title)
        .searchable(text: $search, prompt: "Name, description, or unsupported reason")
    }
}

struct PortholeCapabilityLabel: View {
    let capability: PortholeCapability

    var body: some View {
        VStack(alignment: .leading) {
            Text(capability.name)
            switch capability.availability {
                case .callable:
                    Text(effectSummary)
                        .font(.caption).foregroundStyle(.secondary)
                case .inspectable:
                    Text("Inspect only").font(.caption).foregroundStyle(.secondary)
                case let .unsupported(reason):
                    Text(reason).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var effectSummary: String {
        switch capability.effect {
            case .read: "Read"
            case .isolated: "Isolated action"
            case .mutation, .unknown: "Requires review"
        }
    }
}
