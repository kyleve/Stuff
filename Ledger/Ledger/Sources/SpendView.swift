import LedgerCore
import SwiftUI

/// The menu-bar popover: the current billing cycle's Cursor spend, plus a
/// footer with Refresh, Settings, and Quit. Renders the single
/// ``LedgerServices/LoadState`` — spinner, error, or value — so the three
/// states can never overlap.
struct SpendView: View {
    @Bindable var session: LedgerSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("Cursor Spend")
                .font(.headline)
            Spacer()
            if case .loading = session.loadState {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.loadState {
            case .idle, .loading:
                placeholder
            case let .loaded(member):
                loaded(member)
            case let .failed(error):
                failure(error)
        }
    }

    private var placeholder: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(height: 60)
    }

    private func loaded(_ member: MemberSpend) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This cycle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormat.full(member.totalDollars))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 4) {
                if let included = member.includedDollars {
                    breakdownRow("Included usage", CurrencyFormat.full(included))
                }
                breakdownRow("On-demand", CurrencyFormat.full(member.onDemandDollars))
                if let requests = member.fastPremiumRequests {
                    breakdownRow("Usage-based requests", requests.formatted())
                }
            }
            .padding(.top, 2)

            if let updated = session.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
    }

    private func failure(_ error: LedgerServices.LoadError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            if error == .missingCredentials || error == .memberNotFound {
                SettingsLink {
                    Text("Open Settings")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Button {
                session.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Ledger")
        }
        .buttonStyle(.borderless)
    }
}

#if DEBUG
    #Preview {
        SpendView(session: PreviewSupport.loadedSession())
    }
#endif
