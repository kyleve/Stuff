import SwiftUI
import WhereCore

/// One complete picker candidate used by `ViewThatFits`: labeled on roomy
/// widths or icon-only on compact widths.
struct YearModeSegments: View {
    @Binding var mode: YearViewMode
    let showsTitles: Bool

    @Namespace private var selection
    @Environment(\.stylesheet) private var stylesheet

    private var style: WhereStylesheet.YearOverviewStyle.Picker {
        stylesheet.yearOverview.picker
    }

    var body: some View {
        HStack(spacing: stylesheet.spacing.xxSmall) {
            ForEach(YearViewMode.allCases, id: \.self) { candidate in
                Button {
                    select(candidate)
                } label: {
                    if showsTitles {
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .labelStyle(.titleAndIcon)
                            .fixedSize()
                    } else {
                        Label(candidate.title, systemImage: candidate.systemImage)
                            .labelStyle(.iconOnly)
                    }
                }
                .imageScale(.large)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, style.horizontalPadding)
                .padding(.vertical, style.verticalPadding)
                .frame(minWidth: style.segmentMinSize, minHeight: style.segmentMinSize)
                .foregroundStyle(
                    candidate == mode ? Color(.systemBackground) : Color.primary,
                )
                .contentShape(.capsule)
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: candidate, in: selection, isSource: true)
                .accessibilityAddTraits(candidate == mode ? [.isSelected] : [])
            }
        }
        // Like a system segmented control, the picker keeps fixed icon geometry;
        // every segment still exposes its full accessibility label.
        .dynamicTypeSize(...DynamicTypeSize.large)
        .padding(stylesheet.spacing.small)
        .background {
            Capsule()
                .fill(Color.primary)
                .matchedGeometryEffect(id: mode, in: selection, isSource: false)
        }
        .background {
            Color.clear.glassEffect(.regular, in: .capsule)
        }
    }

    private func select(_ candidate: YearViewMode) {
        guard candidate != mode else { return }
        withAnimation(style.selectionAnimation) { mode = candidate }
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var mode = YearViewMode.breakdown
        YearModeSegments(mode: $mode, showsTitles: false)
            .whereBroadwayRoot()
    }
#endif
