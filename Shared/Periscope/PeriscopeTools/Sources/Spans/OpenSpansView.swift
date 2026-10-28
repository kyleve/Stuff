import PeriscopeCore
import SFSafeSymbols
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
        .periscopeBroadwayRoot()
    }

    @ViewBuilder
    private func content(spans: [OpenSpan], now: ContinuousClock.Instant) -> some View {
        if spans.isEmpty {
            ContentUnavailableView(
                "No Open Spans",
                systemSymbol: .pointBottomleftForwardToPointToprightScurvepath,
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
        return LogScope.ancestry(of: primary) { system.scope(for: $0) }
            .map(\.name)
            .joined(separator: " / ")
    }
}

private struct OpenSpanRow: View {
    let span: OpenSpan
    let now: ContinuousClock.Instant
    let scopePath: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let row = stylesheet.row.comfortable
        let type = stylesheet.typography
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            HStack(spacing: row.headerSpacing) {
                Text(span.name)
                    .font(type.spanName)
                Spacer()
                Text((now - span.start).formatted())
                    .font(type.spanAge)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: row.headerSpacing) {
                Text(lifetimeLabel)
                    .font(type.spanDetail)
                    .foregroundStyle(.secondary)
                if !scopePath.isEmpty {
                    Text(scopePath)
                        .font(type.spanDetail)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, row.verticalPadding)
    }

    private var lifetimeLabel: String {
        switch span.lifetime {
            case .scoped: "scoped"
            case let .bounded(budget): "budget \(budget.formatted())"
            case .indefinite: "indefinite"
        }
    }
}
