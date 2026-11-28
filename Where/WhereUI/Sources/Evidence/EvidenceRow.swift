import SFSafeSymbols
import SwiftUI
import WhereCore

/// One evidence row: kind glyph, kind name, capture date, and a note snippet.
struct EvidenceRow: View {
    let evidence: Evidence

    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        HStack(spacing: stylesheet.spacing.large) {
            Image(systemSymbol: evidence.kind.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: stylesheet.size.statusIconWidth)
            VStack(alignment: .leading, spacing: stylesheet.spacing.xxSmall) {
                Text(evidence.kind.displayName)
                    .font(.headline)
                Text(evidence.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = evidence.note, !note.isEmpty {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, stylesheet.spacing.xxSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            WhereFormat.evidenceRowAccessibility(kind: evidence.kind, date: evidence.capturedAt),
        )
        // Log View Mode: reveal an inspect badge that opens this archive's
        // evidence-scope events. A no-op in release.
        .debugLogInspectable(WhereLog.evidence)
    }
}

#if DEBUG
    #Preview("Evidence row") {
        if let evidence = PreviewSupport.sampleEvidence().first {
            EvidenceRow(evidence: evidence).padding().whereBroadwayRoot()
        }
    }
#endif
