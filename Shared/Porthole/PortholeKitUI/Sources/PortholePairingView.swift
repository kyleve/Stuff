import PortholeKit
import SwiftUI

/// The device-side pairing and status surface: start/stop advertising, show the
/// pending pairing code, list paired hosts (swipe to revoke), and show the
/// active session count. Broadway-styled; drop it into a developer menu.
///
/// Seeds its own Broadway root so it styles correctly with or without a host app
/// root; the content reads `@Environment(\.stylesheet)`.
public struct PortholePairingView: View {
    private let porthole: Porthole

    public init(porthole: Porthole) {
        self.porthole = porthole
    }

    public var body: some View {
        PairingContent(porthole: porthole)
            .portholeBroadwayRoot()
    }
}

private struct PairingContent: View {
    let porthole: Porthole
    @Environment(\.stylesheet) private var stylesheet
    @State private var isShowingError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            if porthole.state.isAdvertising {
                advertisingSection
                pairedHostsSection
            } else {
                idleSection
            }
        }
        .alert("Couldn't start Porthole", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var idleSection: some View {
        Section {
            Button("Start Pairing") { start() }
        } footer: {
            Text(
                "Advertise \(porthole.configuration.appName) on the local network so a paired Mac can connect.",
            )
        }
    }

    private var advertisingSection: some View {
        Section {
            Label(
                "Advertising as \(porthole.configuration.appName)",
                systemImage: "dot.radiowaves.left.and.right",
            )
            .foregroundStyle(stylesheet.palette.advertising)
            if let code = porthole.state.pendingPairingCode {
                PairingCodeDisplay(code: code)
            }
            HStack {
                Text("Active sessions")
                Spacer()
                Text("\(porthole.state.activeSessionCount)")
                    .foregroundStyle(stylesheet.palette.sessionBadge)
                    .monospacedDigit()
            }
            .font(stylesheet.typography.body)
            Button("Stop", role: .destructive) { porthole.stop() }
        } footer: {
            Text("Enter the code above on the Mac when it prompts you.")
        }
    }

    @ViewBuilder private var pairedHostsSection: some View {
        if !porthole.state.pairedHosts.isEmpty {
            Section("Paired Macs") {
                ForEach(porthole.state.pairedHosts) { host in
                    PairedHostRow(host: host)
                        .swipeActions {
                            Button("Revoke", role: .destructive) { revoke(host) }
                        }
                }
            }
        }
    }

    private func start() {
        do {
            try porthole.start()
        } catch {
            errorMessage = String(describing: error)
            isShowingError = true
        }
    }

    private func revoke(_ host: PairedHost) {
        Task {
            do {
                try await porthole.revoke(host.pairingID)
            } catch {
                errorMessage = String(describing: error)
                isShowingError = true
            }
        }
    }
}

/// The pending 6-digit pairing code, shown large and spaced for reading aloud.
private struct PairingCodeDisplay: View {
    let code: String
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        Text(code)
            .font(stylesheet.code.font)
            .tracking(stylesheet.code.digitTracking)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, stylesheet.code.verticalPadding)
            .accessibilityLabel("Pairing code \(code.map(String.init).joined(separator: " "))")
    }
}

/// One paired Mac row: name and when it paired.
private struct PairedHostRow: View {
    let host: PairedHost
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        VStack(alignment: .leading, spacing: stylesheet.spacing.small / 2) {
            Text(host.name)
                .font(stylesheet.typography.hostName)
            Text("Paired \(host.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(stylesheet.typography.hostDetail)
                .foregroundStyle(stylesheet.palette.idle)
        }
    }
}

#if DEBUG
    #Preview {
        PortholePairingView(
            porthole: Porthole(configuration: PortholeConfiguration(appName: "Where")),
        )
    }
#endif
