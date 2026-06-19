import CodeGraphModel
import SwiftUI

/// A single node rendered as a rounded "chip": glyph + name, with affordances
/// for expanding members, and selection / pin emphasis.
///
/// `Equatable` (closure excluded — it only ever captures the stable node id) so
/// `.equatable()` can skip re-rendering unchanged chips during drags/animations.
struct NodeChipView: View, Equatable {
    let node: Node
    let isSelected: Bool
    let isPinned: Bool
    let memberCount: Int
    let isExpanded: Bool
    let isDimmed: Bool
    let onToggleExpand: () -> Void

    static func == (lhs: NodeChipView, rhs: NodeChipView) -> Bool {
        lhs.node == rhs.node
            && lhs.isSelected == rhs.isSelected
            && lhs.isPinned == rhs.isPinned
            && lhs.memberCount == rhs.memberCount
            && lhs.isExpanded == rhs.isExpanded
            && lhs.isDimmed == rhs.isDimmed
    }

    private var accent: Color {
        GraphStyle.color(for: node.kind)
    }

    var body: some View {
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
            if memberCount > 0 {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" :
                        "chevron.right.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background {
            Capsule(style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            accent.opacity(node.origin == .external ? 0.45 : 0.9),
                            lineWidth: isSelected ? 2.5 : 1.2,
                        )
                }
        }
        .opacity(isDimmed ? 0.28 : (node.origin == .external ? 0.85 : 1))
        .shadow(
            color: isSelected ? accent.opacity(0.55) : .black.opacity(0.12),
            radius: isSelected ? 7 : 2,
            y: 1,
        )
        .fixedSize()
    }
}
