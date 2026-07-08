import PeriscopeCore
import SwiftUI

/// The open-spans developer surface: every span currently open via
/// `begin(for:)`, longest running first, with ticking ages, lifetimes, and
/// scope paths — "what's in flight right now, and is anything stuck".
///
/// Reads the `Periscope` system directly (open spans are system state, not
/// store history) and re-snapshots once a second. Designed to be pushed
/// inside an existing `NavigationStack` from a developer menu.
public struct OpenSpansView: View {
    private let system: Periscope

    public init(system: Periscope) {
        self.system = system
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            content(spans: system.openSpans(), now: ContinuousClock().now)
        }
        .navigationTitle("Open Spans")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(spans: [OpenSpan], now: ContinuousClock.Instant) -> some View {
        if spans.isEmpty {
            ContentUnavailableView(
                "No Open Spans",
                systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                description: Text("Spans opened with begin(for:) appear here while they run."),
            )
        } else {
            List(spans, id: \.id) { span in
                OpenSpanRow(span: span, now: now, scopePath: scopePath(for: span))
            }
            .listStyle(.plain)
        }
    }

    private func scopePath(for span: OpenSpan) -> String {
        guard let primary = span.scopes.first else { return "" }
        var names: [String] = []
        var next: ScopeID? = primary
        while let id = next, let scope = system.scope(for: id) {
            names.append(scope.name)
            next = scope.parentID
        }
        return names.reversed().joined(separator: " / ")
    }
}

private struct OpenSpanRow: View {
    let span: OpenSpan
    let now: ContinuousClock.Instant
    let scopePath: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(span.name)
                    .font(.callout.weight(.medium))
                Spacer()
                Text((now - span.start).formatted())
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(lifetimeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !scopePath.isEmpty {
                    Text(scopePath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var lifetimeLabel: String {
        switch span.lifetime {
            case .scoped: "scoped"
            case let .bounded(budget): "budget \(budget.formatted())"
            case .indefinite: "indefinite"
        }
    }
}
