import PortholeClientKit
import SwiftUI

@main
struct PortholeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .portholeAppBroadwayRoot()
                .task { model.onAppear() }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationTitle("Porthole")
        } detail: {
            if let app = model.connectedApp {
                ConnectorBrowserView(model: model, app: app)
            } else {
                ContentUnavailableView(
                    "Select a paired app",
                    systemImage: "app.connected.to.app.below.fill",
                )
            }
        }
        .sheet(item: $model.pairingInProgress) { app in
            PairSheet(model: model, app: app)
        }
        .safeAreaInset(edge: .bottom) {
            if let status = model.statusMessage {
                Text(status)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.thinMaterial)
            }
        }
    }
}

struct SidebarView: View {
    @Bindable var model: AppModel

    private var unpaired: [DiscoveredApp] {
        let pairedBundles = Set(model.pairedApps.map(\.bundleID))
        return model.discovered.filter { !pairedBundles.contains($0.bundleID) }
    }

    var body: some View {
        List(selection: $model.selection) {
            Section("Paired") {
                if model.pairedApps.isEmpty {
                    Text("No paired apps").foregroundStyle(.secondary)
                }
                ForEach(model.pairedApps) { app in
                    VStack(alignment: .leading) {
                        Text(app.appName)
                        Text(app.deviceName).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(app.pairingID)
                    .swipeActions {
                        Button("Unpair", role: .destructive) { model.unpair(app) }
                    }
                }
            }
            Section("Discovered") {
                if unpaired.isEmpty {
                    Text("Searching…").foregroundStyle(.secondary)
                }
                ForEach(unpaired) { app in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(app.appName)
                            Text(app.deviceName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Pair") { model.beginPairing(with: app) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .onChange(of: model.selection) { _, newValue in
            guard let id = newValue,
                  let app = model.pairedApps.first(where: { $0.pairingID == id }) else { return }
            Task { await model.select(app) }
        }
    }
}

struct PairSheet: View {
    @Bindable var model: AppModel
    let app: DiscoveredApp
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "A 6-digit code is showing on \(app.appName) on \(app.deviceName). Enter it to pair.",
                    )
                    TextField("Code", text: $code)
                        .font(.system(.title2, design: .monospaced))
                }
            }
            .navigationTitle("Pair with \(app.appName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.cancelPairing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { model.submitCode(code) }
                        .disabled(code.isEmpty)
                }
            }
        }
    }
}
