import PortholeRemote
import SFSafeSymbols
import SwiftUI
#if canImport(UIKit)
    import SnapshotKit
#endif

/// Controls the host listener separately from local debugging and provider access.
public struct PortholeHostingView: View {
    @Bindable private var model: PortholeHostPresentationModel

    public init(model: PortholeHostPresentationModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("Remote access") {
                Text(
                    "Remote access starts only when you enable it here. Enrolled clients use mutual TLS and the same operation review policy.",
                )
                switch model.state {
                    case .disabled:
                        Button("Enable remote access") { Task { await model.enable() } }
                    case .creating, .starting:
                        ProgressView("Starting remote access…")
                        Button("Cancel", role: .cancel) { Task { await model.disable() } }
                    case .active:
                        Label("Remote access is enabled", systemSymbol: .network)
                        Button("Disable remote access", role: .destructive) {
                            Task { await model.disable() }
                        }
                    case let .failed(message):
                        Label(message, systemSymbol: .exclamationmarkTriangle)
                        Button("Try enabling again") { Task { await model.enable() } }
                }
            }
            if let session = model.activeSession { PortholeHostSessionView(session: session) }
        }
        .navigationTitle("Remote access")
    }
}

#if DEBUG && canImport(UIKit)
    #Preview { PortholeHostingView.snapshotPreviews }
#endif

#if canImport(UIKit)
    extension PortholeHostingView: SnapshotProviding {
        public static var snapshots: [SnapshotCase] {
            let disabled = PortholeHostingSnapshotFixture(activate: false)
            let enrollment = PortholeHostingSnapshotFixture(activate: true)
            SnapshotCase(name: "Disabled", configurations: .fullContentScreenDefaults) {
                PortholeHostingSnapshotSurface(fixture: disabled)
            }
            SnapshotCase(
                name: "Enrollment",
                configurations: .fullContentScreenDefaults,
                onReadyToMeasure: { await enrollment.prepare() },
                onReadyToSnapshot: { await enrollment.prepare() },
            ) {
                PortholeHostingSnapshotSurface(fixture: enrollment)
            }
        }
    }
#endif

private struct PortholeHostSessionView: View {
    let session: PortholeHostedSession

    var body: some View {
        Section("Enroll a client") {
            switch session.enrollment {
                case .closed:
                    Button("Create one-time invitation") {
                        Task { await session.createInvitation() }
                    }
                case .creating: ProgressView("Creating invitation…")
                case let .invitation(invitation):
                    PortholeInvitationCodeView(image: invitation.image)
                    LabeledContent("Expires") {
                        Text(invitation.expiresAt, format: .dateTime.hour().minute().second())
                    }
                    Text(invitation.text).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink("Copy or share invitation", item: invitation.text)
                    Button("Close enrollment", role: .cancel) {
                        Task { await session.cancelInvitation() }
                    }
                case let .failed(message):
                    Text(message)
                    Button("Create another invitation") { Task { await session.createInvitation() }
                    }
            }
        }
        Section("Enrolled clients") {
            if session.peers
                .isEmpty { Text("No clients are enrolled.").foregroundStyle(.secondary) }
            ForEach(session.peers) { peer in
                VStack(alignment: .leading) {
                    Text(peer.name)
                    Text(peer.enrolledAt, format: .dateTime).font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Revoke \(peer.name)", role: .destructive) {
                        Task { await session.revoke(peer) }
                    }
                }
            }
            if let error = session.revocationError { Text(error).foregroundStyle(.secondary) }
        }
        .task(id: session.id) { await session.observe() }
    }
}
