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
        HStack(spacing: 8) {
            Text("Cursor Spend")
                .font(.headline)
            Spacer()
            if session.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
            if let plan = planLabel {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .clipShape(.capsule)
            }
        }
    }

    /// The plan tier for the header badge, shown once loaded.
    private var planLabel: String? {
        if case let .loaded(snapshot) = session.loadState {
            snapshot.membershipType.capitalized
        } else {
            nil
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

            if snapshot.autoFractionUsed != nil || snapshot.apiFractionUsed != nil {
                includedUsage(auto: snapshot.autoFractionUsed, api: snapshot.apiFractionUsed)
            }

            if !snapshot.modelShares.isEmpty {
                models(snapshot.modelShares)
            }
        }
    }

    /// Included allowance shown as two side-by-side gauges — first-party (Auto)
    /// and third-party (API) — since a single blended figure hides that one
    /// pool can be exhausted while the other is barely touched.
    private func includedUsage(auto: Double?, api: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Included usage")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                if let auto {
                    usageGauge(label: "First-party", fraction: auto, color: .teal)
                }
                if let api {
                    usageGauge(label: "API", fraction: api, color: .blue)
                }
            }
        }
    }

    private func usageGauge(label: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .lineLimit(1)
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            ShareBar(segments: [ShareSegment(color: color, fraction: fraction)])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    fraction: model.fraction,
                    segments: [ShareSegment(color: model.color, fraction: model.fraction)],
                ) {
                    ModelLabel(name: ModelName.parse(model.name))
                }
            }

            if !minors.isEmpty {
                shareRow(
                    fraction: minorsTotal,
                    segments: minors.map { ShareSegment(color: $0.color, fraction: $0.fraction) },
                ) {
                    Text("Other models")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                // Legend so the rolled-up colors are identifiable.
                ForEach(minors) { model in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.color)
                            .frame(width: 7, height: 7)
                        ModelLabel(name: ModelName.parse(model.name))
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

    private func shareRow(
        fraction: Double,
        segments: [ShareSegment],
        @ViewBuilder label: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                label()
                Spacer()
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            ShareBar(segments: segments)
        }
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
            if let updated = session.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

/// Renders a parsed ``ModelName`` — the friendly name plus small badge chips
/// (reasoning effort, speed, mode). Adopts the ambient font for the name; the
/// badges stay compact.
private struct ModelLabel: View {
    let name: ModelName

    var body: some View {
        HStack(spacing: 4) {
            Text(name.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            ForEach(name.badges, id: \.self) { badge in
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.2), in: .capsule)
                    .foregroundStyle(.secondary)
            }
        }
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
