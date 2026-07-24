import Foundation
import PortholeCore

/// An immutable, `Sendable` dispatch snapshot the session router uses off the
/// main actor: the advertised manifests plus ref → handler lookup tables. Built
/// once per session from the registry (derive, don't re-derive) so request
/// dispatch never hops back to the main actor to resolve a connector.
struct ResolvedConnectors {
    var manifests: [ConnectorManifest]
    var actions: [PortholeActionRef: PortholeAction]
    var dataSources: [PortholeDataSourceRef: PortholeDataSource]

    func action(
        _ ref: PortholeActionRef,
        hasConnector: (PortholeConnectorID) -> Bool,
    ) -> Result<PortholeAction, PortholeError> {
        if let action = actions[ref] { return .success(action) }
        return .failure(hasConnector(ref.connector) ? .actionNotFound(ref) :
            .connectorNotFound(ref.connector))
    }

    func dataSource(
        _ ref: PortholeDataSourceRef,
        hasConnector: (PortholeConnectorID) -> Bool,
    ) -> Result<PortholeDataSource, PortholeError> {
        if let source = dataSources[ref] { return .success(source) }
        return .failure(hasConnector(ref.connector) ? .sourceNotFound(ref) :
            .connectorNotFound(ref.connector))
    }

    var connectorIDs: Set<PortholeConnectorID> {
        Set(manifests.map(\.connector.id))
    }
}

/// Holds the app's registered connectors on the main actor and resolves them
/// into a `Sendable` dispatch snapshot. A duplicate connector id is a programmer
/// error (`assertionFailure` in debug, ignored in release) — connector ids are a
/// fixed, curated set.
@MainActor
final class ConnectorRegistry {
    private var connectors: [PortholeConnectorID: any PortholeConnector] = [:]
    private var order: [PortholeConnectorID] = []

    func register(_ connector: some PortholeConnector) {
        let id = connector.descriptor.id
        guard connectors[id] == nil else {
            assertionFailure("Duplicate Porthole connector id `\(id)`")
            PortholeLog.runtime
                .error("Ignoring duplicate Porthole connector id \(id.rawValue, privacy: .public)")
            return
        }
        connectors[id] = connector
        order.append(id)
    }

    func resolve() -> ResolvedConnectors {
        var manifests: [ConnectorManifest] = []
        var actions: [PortholeActionRef: PortholeAction] = [:]
        var dataSources: [PortholeDataSourceRef: PortholeDataSource] = [:]

        for id in order {
            guard let connector = connectors[id] else { continue }
            let connectorActions = connector.actions()
            let connectorSources = connector.dataSources()
            for action in connectorActions {
                actions[PortholeActionRef(connector: id, action: action.descriptor.id)] = action
            }
            for source in connectorSources {
                dataSources[PortholeDataSourceRef(connector: id, source: source.descriptor.id)] =
                    source
            }
            manifests.append(ConnectorManifest(
                connector: connector.descriptor,
                actions: connectorActions.map(\.descriptor),
                dataSources: connectorSources.map(\.descriptor),
            ))
        }
        return ResolvedConnectors(manifests: manifests, actions: actions, dataSources: dataSources)
    }
}
