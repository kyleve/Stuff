import PortholeClientKit
import PortholeCore
import SwiftUI

/// Lists the connected app's connectors and routes into their actions and data
/// sources.
struct ConnectorBrowserView: View {
    let model: AppModel
    let app: PairedApp

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.manifests, id: \.connector.id) { manifest in
                    Section(manifest.connector.title) {
                        ForEach(manifest.dataSources, id: \.id) { source in
                            if let session = model.activeSession {
                                NavigationLink {
                                    SourceTableView(
                                        model: SourceTableModel(
                                            descriptor: source,
                                            connector: manifest.connector.id,
                                            session: session,
                                        ),
                                    )
                                } label: {
                                    Label(
                                        source.title,
                                        systemImage: source
                                            .supportsSubscription ? "dot.radiowaves.up.forward" :
                                            "tablecells",
                                    )
                                }
                            }
                        }
                        ForEach(manifest.actions, id: \.id) { action in
                            if let session = model.activeSession {
                                NavigationLink {
                                    ActionFormView(
                                        model: ActionFormModel(
                                            descriptor: action,
                                            connector: manifest.connector.id,
                                            session: session,
                                        ),
                                    )
                                } label: {
                                    Label(
                                        action.title,
                                        systemImage: action
                                            .isDestructive ? "exclamationmark.triangle" : "bolt",
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(app.appName)
        }
    }
}
