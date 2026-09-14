import CreditKit
import os
import PortholeRemote
import PortholeUI
import SwiftUI

@main
struct PortholeApp: App {
    private enum Destination: Hashable { case connect, acknowledgements }
    @State private var destination = Destination.connect
    @State private var attribution: Result<AttributionManifest, any Error>?
    @State private var model = PortholeRemotePresentationModel(
        keychain: PortholeRemoteKeychain(service: "client", accessGroup: nil),
        clientName: "Porthole",
    )

    var body: some Scene {
        WindowGroup {
            TabView(selection: $destination) {
                Tab(value: .connect) { PortholeRemoteView(model: model) } label: { Text("Connect") }
                Tab(value: .acknowledgements) {
                    NavigationStack {
                        if let attribution { PortholeAcknowledgementsView(report: attribution) }
                        else { ProgressView("Loading acknowledgements…") }
                    }
                    .task { loadAttribution() }
                } label: { Text("Acknowledgements") }
            }
        }
    }

    private func loadAttribution() {
        guard attribution == nil else { return }
        do { attribution = try .success(AttributionManifest.load(
            from: .main,
            resource: "attribution",
        )) } catch {
            Logger(subsystem: "com.stuff.porthole", category: "Attribution")
                .error(
                    "Attribution report failed: \(error.localizedDescription, privacy: .private)",
                )
            attribution = .failure(error)
        }
    }
}
