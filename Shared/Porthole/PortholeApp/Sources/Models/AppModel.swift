import Foundation
import PortholeClientKit
import PortholeCore

/// The app's top-level coordinator: tracks paired and discovered apps, owns the
/// active session to the selected app, and drives pairing. `@MainActor` +
/// `@Observable` for SwiftUI.
@MainActor
@Observable
final class AppModel {
    var pairedApps: [PairedApp] = []
    var discovered: [DiscoveredApp] = []
    var selection: UUID?
    private(set) var manifests: [ConnectorManifest] = []
    private(set) var connectedApp: PairedApp?
    var statusMessage: String?

    /// A pairing awaiting the user's code entry.
    var pairingInProgress: DiscoveredApp?
    private var codeContinuation: CheckedContinuation<String, Never>?

    private let client = PortholeClient()
    private let pairingClient = PortholePairingClient()
    private var session: PortholeSession?
    private var browseTask: Task<Void, Never>?

    func onAppear() {
        reloadPaired()
        startBrowsing()
    }

    func reloadPaired() {
        pairedApps = (try? client.pairedApps()) ?? []
    }

    private func startBrowsing() {
        browseTask?.cancel()
        browseTask = Task { [weak self] in
            for await apps in PortholeBrowser().discovered() {
                self?.discovered = apps
            }
        }
    }

    /// Active `PortholeSession` for connector screens (nil until connected).
    var activeSession: PortholeSession? {
        session
    }

    func select(_ paired: PairedApp) async {
        selection = paired.pairingID
        await disconnect()
        statusMessage = "Connecting to \(paired.appName)…"
        do {
            let session = try await client.connect(to: paired)
            self.session = session
            connectedApp = paired
            manifests = try await session.manifest()
            statusMessage = nil
        } catch {
            statusMessage = "Couldn't connect: \(error)"
            manifests = []
            connectedApp = nil
        }
    }

    func disconnect() async {
        if let session { await session.close() }
        session = nil
        connectedApp = nil
        manifests = []
    }

    // MARK: - Pairing

    func beginPairing(with app: DiscoveredApp) {
        pairingInProgress = app
        Task { [weak self] in
            guard let self else { return }
            do {
                let paired = try await pairingClient.pair(with: app) {
                    await self.awaitCode()
                }
                reloadPaired()
                pairingInProgress = nil
                statusMessage = "Paired with \(paired.appName)."
            } catch {
                pairingInProgress = nil
                codeContinuation = nil
                statusMessage = "Pairing failed: \(error)"
            }
        }
    }

    /// Called by the pairing sheet once the user enters the device's code.
    func submitCode(_ code: String) {
        codeContinuation?.resume(returning: code)
        codeContinuation = nil
    }

    func cancelPairing() {
        codeContinuation?.resume(returning: "")
        codeContinuation = nil
        pairingInProgress = nil
    }

    private func awaitCode() async -> String {
        await withCheckedContinuation { continuation in
            codeContinuation = continuation
        }
    }

    func unpair(_ paired: PairedApp) {
        try? client.unpair(paired)
        reloadPaired()
        if selection == paired.pairingID {
            selection = nil
            Task { await disconnect() }
        }
    }
}
