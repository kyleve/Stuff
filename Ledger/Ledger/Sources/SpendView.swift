import LedgerCore
import SwiftUI

/// The menu-bar popover: the current billing cycle's Cursor spend and the
/// year-to-date total, plus a footer with Refresh, Settings, and Quit. Renders
/// the single ``LedgerServices/LoadState`` — spinner, error, or value — so the
/// three states can never overlap.
struct SpendView: View {
    @Bindable var session: LedgerSession

    /// Models at or above this share get their own bar; the rest are rolled up.
    private static let rollupThreshold = 0.20

    /// Distinct colors assigned to models in share order (cycled if exhausted).
    private static let palette: [Color] = [
        .blue,
        .green,
        .orange,
        .purple,
        .pink,
        .teal,
        .indigo,
        .yellow,
        .red,
        .mint,
    ]

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
                breakdownRow("Plan", snapshot.membershipType.capitalized)
            }

            if let fraction = snapshot.includedFractionUsed {
                includedUsage(fraction, messages: snapshot.usageMessages)
            }

            if !snapshot.modelShares.isEmpty {
                models(snapshot.modelShares)
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

    /// Models this cycle: each model with ≥20% share gets its own bar; the rest
    /// roll into a single multi-colored "Other models" bar (one segment per
    /// model), with a compact legend.
    private func models(_ shares: [ModelShare]) -> some View {
        let colored = shares.enumerated().map { index, share in
            ColoredShare(
                name: share.name,
                fraction: share.fraction,
                color: Self.palette[index % Self.palette.count],
            )
        }
        let majors = colored.filter { $0.fraction >= Self.rollupThreshold }
        let minors = colored.filter { $0.fraction < Self.rollupThreshold }
        let minorsTotal = minors.reduce(0) { $0 + $1.fraction }

        return VStack(alignment: .leading, spacing: 6) {
            Text("Top models this cycle")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(majors) { model in
                shareRow(
                    label: model.name,
                    fraction: model.fraction,
                    segments: [ShareSegment(color: model.color, fraction: model.fraction)],
                )
            }

            if !minors.isEmpty {
                shareRow(
                    label: "Other models",
                    fraction: minorsTotal,
                    segments: minors.map { ShareSegment(color: $0.color, fraction: $0.fraction) },
                )
                // Legend so the rolled-up colors are identifiable.
                ForEach(minors) { model in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.color)
                            .frame(width: 7, height: 7)
                        Text(model.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(model.fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func shareRow(label: String, fraction: Double, segments: [ShareSegment]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            ShareBar(segments: segments)
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

/// A model paired with its display color for the models breakdown.
private struct ColoredShare: Identifiable {
    let name: String
    let fraction: Double
    let color: Color

    var id: String {
        name
    }
}

/// One colored slice of a ``ShareBar`` (its width is `fraction` of the track).
private struct ShareSegment {
    let color: Color
    let fraction: Double
}

/// A rounded track filled with one or more colored segments, each sized as a
/// fraction (0...1) of the full width. A single segment reads as a simple bar;
/// several read as a stacked breakdown.
private struct ShareBar: View {
    let segments: [ShareSegment]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segment.color
                        .frame(width: max(
                            0,
                            geometry.size.width * min(max(segment.fraction, 0), 1),
                        ))
                }
            }
        }
        .frame(height: 6)
        .background(Color.secondary.opacity(0.15))
        .clipShape(.capsule)
    }
}

#if DEBUG
    #Preview {
        SpendView(session: PreviewSupport.loadedSession())
    }
#endif
