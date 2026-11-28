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
            OpenSpansList(
                spans: system.openSpans(),
                now: ContinuousClock().now,
                scopePath: scopePath(for:),
            )
        }
        .navigationTitle("Open Spans")
        .navigationBarTitleDisplayMode(.inline)
        .periscopeBroadwayRoot()
    }

    private func scopePath(for span: OpenSpan) -> String {
        guard let primary = span.scopes.first else { return "" }
        return LogScope.ancestry(of: primary) { system.scope(for: $0) }
            .map(\.name)
            .joined(separator: " / ")
    }
}

private struct OpenSpansList: View {
    let spans: [OpenSpan]
    let now: ContinuousClock.Instant
    let scopePath: (OpenSpan) -> String

    var body: some View {
        if spans.isEmpty {
            ContentUnavailableView(
                "No Open Spans",
                systemSymbol: .pointBottomleftForwardToPointToprightScurvepath,
                description: Text("Spans opened with begin(for:) appear here while they run."),
            )
        } else {
            List(spans, id: \.id) { span in
                OpenSpanRow(span: span, now: now, scopePath: scopePath(span))
            }
            .listStyle(.plain)
        }
    }
}

private struct OpenSpanRow: View {
    let span: OpenSpan
    let now: ContinuousClock.Instant
    let scopePath: String

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        let row = stylesheet.row.comfortable
        VStack(alignment: .leading, spacing: row.lineSpacing) {
            OpenSpanHeader(span: span, now: now)
            OpenSpanLifetime(span: span, scopePath: scopePath)
        }
        .padding(.vertical, row.verticalPadding)
    }
}

private struct OpenSpanHeader: View {
    let span: OpenSpan
    let now: ContinuousClock.Instant
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.row.comfortable.headerSpacing) {
            Text(span.name)
                .font(stylesheet.typography.spanName)
            Spacer()
            Text((now - span.start).formatted())
                .font(stylesheet.typography.spanAge)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct OpenSpanLifetime: View {
    let span: OpenSpan
    let scopePath: String
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.row.comfortable.headerSpacing) {
            Text(lifetimeLabel)
                .font(stylesheet.typography.spanDetail)
                .foregroundStyle(.secondary)
            if !scopePath.isEmpty {
                Text(scopePath)
                    .font(stylesheet.typography.spanDetail)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var lifetimeLabel: String {
        switch span.lifetime {
            case .scoped: "scoped"
            case let .bounded(budget): "budget \(budget.formatted())"
            case .indefinite: "indefinite"
        }
    }
}

#if DEBUG
    #Preview {
        let now = ContinuousClock().now
        let span = OpenSpan(
            id: SpanID(),
            name: "Refresh catalog",
            start: now - .seconds(36),
            lifetime: .bounded(budget: .seconds(120)),
            beganRecorded: true,
            scopes: [],
            tags: [],
        )
        OpenSpansList(spans: [span], now: now, scopePath: { _ in "Preview" })
            .periscopeBroadwayRoot()
    }
#endif
