import LedgerCore
import SwiftUI

/// The menu-bar popover: the current billing cycle's Cursor spend and the
/// year-to-date total, plus a footer with Refresh, Settings, and Quit. Renders
/// the single ``LedgerServices/LoadState`` — spinner, error, or value — so the
/// three states can never overlap.
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
            if session.isRefreshing {
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
            case let .loaded(snapshot):
                loaded(snapshot)
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

    private func loaded(_ snapshot: SpendSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This cycle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormat.dollars(snapshot.currentCycleDollars))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: snapshot.currentCycleDollars))
                    .animation(.default, value: snapshot.currentCycleDollars)
                if let range = cycleRange(snapshot) {
                    Text(range)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                breakdownRow("This year", CurrencyFormat.dollars(snapshot.yearToDateDollars))
                breakdownRow("Plan", snapshot.membershipType.capitalized)
            }

            if let fraction = snapshot.includedFractionUsed {
                includedUsage(fraction, messages: snapshot.usageMessages)
            }

            if !snapshot.topModels.isEmpty {
                topModels(snapshot.topModels)
            }

            if let updated = session.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func includedUsage(_ fraction: Double, messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Included usage")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            .font(.callout)
            ProgressView(value: min(max(fraction, 0), 1))
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func topModels(_ models: [ModelShare]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top models this cycle")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(models) { model in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(model.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    ProgressView(value: min(max(model.fraction, 0), 1))
                }
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

    private func cycleRange(_ snapshot: SpendSnapshot) -> String? {
        guard let start = snapshot.cycleStart, let end = snapshot.cycleEnd else { return nil }
        let formatter = Date.FormatStyle.dateTime.month(.abbreviated).day()
        return "\(start.formatted(formatter)) – \(end.formatted(formatter))"
    }

    private func failure(_ error: LedgerServices.LoadError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            if error == .missingCredentials || error == .notAuthenticated {
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
