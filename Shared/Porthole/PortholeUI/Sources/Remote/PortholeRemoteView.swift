import PortholeCore
import PortholeRemote
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// Shared Mac and iPad client entry. Pairing is explicit and remote approvals remain on the host
/// device.
public struct PortholeRemoteView: View {
    @Bindable private var model: PortholeRemotePresentationModel
    @Environment(\.portholeStylesheet) private var stylesheet

    public init(model: PortholeRemotePresentationModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Pair with an application") {
                    SecureField("Paste one-time invitation", text: $model.invitation)
                    Button("Pair") { Task { await model.enroll() } }
                        .disabled(model.invitation.isEmpty)
                    switch model.pairing {
                        case .idle: Text(
                                "Enable remote access in the app, then create an invitation.",
                            )
                            .foregroundStyle(.secondary)
                        case .pairing: ProgressView("Pairing…")
                        case let .paired(name): Label(
                                "Paired with \(name)",
                                systemSymbol: .checkmarkCircle,
                            )
                        case let .failed(message): Label(
                                message,
                                systemSymbol: .exclamationmarkTriangle,
                            )
                    }
                }
                Section("Enrolled applications") {
                    if let error = model.savedServersError { Text(error).foregroundStyle(.red) }
                    ForEach(model.servers) { server in
                        Button(server.serviceName) { Task { await model.connect(server: server) } }
                    }
                    if model.servers
                        .isEmpty { Text("No enrolled applications.").foregroundStyle(.secondary) }
                }
                Section("Nearby applications") {
                    ForEach(model.discovered) { application in Text(application.name) }
                    if let error = model.discoveryError { Text(error).foregroundStyle(.red) }
                    if model.discovered
                        .isEmpty
                    { Text("Searching the local network…").foregroundStyle(.secondary)
                    }
                }
                connection
            }
            .navigationTitle("Porthole")
            .task { await model.loadServers(); await model.discover() }
        }
        .portholeBroadwayRoot()
    }

    @ViewBuilder private var connection: some View {
        switch model.connection {
            case .idle: EmptyView()
            case .connecting: Section { ProgressView("Connecting…") }
            case let .failed(message): Section("Connection failed") { Text(message) }
            case let .connected(session):
                Section(session.application.name) {
                    Button("Disconnect") { Task { await model.disconnect() } }
                    ForEach(session.application.scopes, id: \.self) { scope in
                        NavigationLink(scope.id.rawValue) {
                            if let navigation = model.evidenceNavigation {
                                PortholeRemoteScopeView(
                                    model: model,
                                    scope: scope,
                                    navigation: navigation,
                                )
                            } else { Text("The remote session has disconnected.") }
                        }
                    }
                }
        }
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeRemoteView.snapshotPreviews }
#endif

#if canImport(UIKit)
    extension PortholeRemoteView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            SnapshotCase(name: "Pairing", configurations: .fullContentScreenDefaults) {
                PortholeRemoteView(model: PortholeRemotePresentationModel(
                    connector: PortholeRemoteSnapshotConnector(),
                    clientName: "Mac",
                ))
            }
        }
    }
#endif

private struct PortholeRemoteScopeView: View {
    @Bindable var model: PortholeRemotePresentationModel
    let scope: PortholeScopeToken
    let navigation: PortholeEvidenceNavigation

    var body: some View {
        List {
            switch model.scopeState {
                case .idle, .loading: ProgressView("Reading capabilities…")
                case let .failed(message): Text(message)
                case let .loaded(_, snapshot):
                    if let contexts = snapshot.contexts {
                        Section("Captured contexts") {
                            ForEach(contexts) { context in
                                PortholeEvidenceLink(
                                    reference: .context(context),
                                    navigation: navigation,
                                )
                            }
                        }
                    }
                    if let objects = snapshot.objects, !objects.isEmpty {
                        Section("Objects") {
                            ForEach(objects, id: \.id) { reference in
                                PortholeEvidenceLink(
                                    reference: .object(reference),
                                    navigation: navigation,
                                )
                            }
                        }
                    }
                    Section("API coverage") {
                        NavigationLink("All declarations and compilation coverage") {
                            PortholeCoverageView(
                                scope: scope,
                                module: nil,
                                capabilities: snapshot.capabilities,
                                objects: snapshot.objects ?? [],
                                navigation: navigation,
                            )
                            .id(scope)
                        }
                    }
                    Section("Capabilities") {
                        ForEach(snapshot.capabilities
                            .filter {
                                $0.matches(search: model.search)
                            }) { capability in
                                NavigationLink {
                                    PortholeInvocationView(
                                        capability: capability,
                                        objects: snapshot.objects ?? [],
                                        scope: scope,
                                        execute: navigation.execute,
                                    )
                                } label: { PortholeCapabilityLabel(capability: capability) }
                            }
                    }
            }
        }
        .environment(\.portholeEvidenceNavigation, navigation)
        .navigationTitle(scope.id.rawValue)
        .searchable(text: $model.search, prompt: "APIs, types, or modules")
        .task(id: scope) { await model.select(scope: scope) }
        .refreshable { await model.select(scope: scope) }
    }
}
