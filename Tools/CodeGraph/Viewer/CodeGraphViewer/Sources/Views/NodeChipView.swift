import CodeGraphModel
import SwiftUI

/// Geometry shared by the chip renderer and the layout engine so the footprint
/// the layout reserves for a node matches what's actually drawn. Members of a
/// type render as rows *inside* its box (UML-style), capped to ``rowCap`` until
/// expanded.
enum ChipMetrics {
    static let rowCap = 6
    static let minWidth: CGFloat = 116
    static let maxWidth: CGFloat = 280
    static let headerHeight: CGFloat = 30
    static let rowHeight: CGFloat = 17
    static let bodyPadding: CGFloat = 6

    /// Number of member rows shown given the expand state.
    static func shownRowCount(total: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, rowCap)
    }

    /// Estimated footprint of a chip: width clamped to the name / widest shown
    /// row; height grows with the shown rows plus the "+N more" affordance.
    static func size(name: String, rows: [MemberRow], expanded: Bool) -> CGSize {
        let headerWidth = textWidth(name, charWidth: 7) + 50
        guard !rows.isEmpty else {
            return CGSize(width: clampWidth(headerWidth), height: headerHeight)
        }
        let shown = shownRowCount(total: rows.count, expanded: expanded)
        let rowsWidth = rows.prefix(shown).map(rowWidth).max() ?? 0
        let hasMoreRow = rows.count > rowCap
        let width = clampWidth(max(headerWidth, rowsWidth))
        let rowsHeight = CGFloat(shown + (hasMoreRow ? 1 : 0)) * rowHeight
        return CGSize(width: width, height: headerHeight + rowsHeight + bodyPadding)
    }

    private static func clampWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, minWidth), maxWidth)
    }

    private static func rowWidth(_ row: MemberRow) -> CGFloat {
        let label = row.typeName.map { "\(row.name): \($0)" } ?? row.name
        return textWidth(label, charWidth: 6.2) + 32
    }

    /// Cheap monospace-ish estimate; exact text metrics aren't available here and
    /// the chip truncates to the clamped width anyway.
    private static func textWidth(_ string: String, charWidth: CGFloat) -> CGFloat {
        CGFloat(string.count) * charWidth
    }
}

/// A single type rendered as a rounded UML-style box: a header (glyph + name)
/// over a compartment of member rows, with selection / pin emphasis. Types with
/// no members collapse to a compact pill.
///
/// `Equatable` (closures excluded — they only capture the stable node id) so
/// `.equatable()` can skip re-rendering unchanged chips during drags/animations.
struct NodeChipView: View, Equatable {
    let node: Node
    let isSelected: Bool
    let isPinned: Bool
    let rows: [MemberRow]
    let isExpanded: Bool
    let isDimmed: Bool
    let onToggleExpand: () -> Void

    static func == (lhs: NodeChipView, rhs: NodeChipView) -> Bool {
        lhs.node == rhs.node
            && lhs.isSelected == rhs.isSelected
            && lhs.isPinned == rhs.isPinned
            && lhs.rows == rhs.rows
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isDimmed == rhs.isDimmed
    }

    private var accent: Color {
        GraphStyle.color(for: node.kind)
    }

    private var hasMembers: Bool {
        !rows.isEmpty
    }

    private var cornerRadius: CGFloat {
        hasMembers ? 11 : ChipMetrics.headerHeight / 2
    }

    private var shownRows: ArraySlice<MemberRow> {
        rows.prefix(ChipMetrics.shownRowCount(total: rows.count, expanded: isExpanded))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if hasMembers {
                Rectangle()
                    .fill(accent.opacity(0.25))
                    .frame(height: 1)
                memberList
            }
        }
        .frame(
            width: ChipMetrics.size(name: node.name, rows: rows, expanded: isExpanded).width,
            alignment: .leading,
        )
        .background {
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            shape
                .fill(Color(uiColor: .systemBackground))
                .overlay {
                    shape.strokeBorder(
                        accent.opacity(node.origin == .external ? 0.45 : 0.9),
                        lineWidth: isSelected ? 2.5 : 1.2,
                    )
                }
        }
        .opacity(isDimmed ? 0.28 : (node.origin == .external ? 0.85 : 1))
        // Only the selected chip casts a shadow. A per-chip ambient shadow is a
        // blur/compositing pass each, which adds up across many visible nodes;
        // the border already separates chips from edges and the background.
        .shadow(
            color: isSelected ? accent.opacity(0.55) : .clear,
            radius: isSelected ? 7 : 0,
            y: isSelected ? 1 : 0,
        )
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: GraphStyle.symbol(for: node.kind))
                .font(.caption2)
                .foregroundStyle(accent)
            Text(node.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if node.isGeneric {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 7))
                    .foregroundStyle(.secondary)
            }
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: ChipMetrics.headerHeight)
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shownRows) { row($0) }
            if rows.count > ChipMetrics.rowCap {
                Button(action: onToggleExpand) {
                    Text(isExpanded ? "Show less" : "+\(rows.count - ChipMetrics.rowCap) more")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(height: ChipMetrics.rowHeight)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, ChipMetrics.bodyPadding / 2)
    }

    private func row(_ member: MemberRow) -> some View {
        HStack(spacing: 5) {
            Image(systemName: GraphStyle.symbol(for: member.kind))
                .font(.system(size: 8))
                .foregroundStyle(GraphStyle.color(for: member.kind))
                .frame(width: 11)
            Text(label(for: member))
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(height: ChipMetrics.rowHeight)
    }

    private func label(for member: MemberRow) -> String {
        if let typeName = member.typeName {
            "\(member.name): \(typeName)"
        } else {
            member.name
        }
    }
}
