import SwiftUI
import WhereCore

/// The adaptive Liquid Glass picker at the bottom of Your Year. It keeps full
/// icon-and-title segments where they fit, falling back to icon-only segments on
/// compact widths while retaining the same accessible labels.
struct YearModePicker: View {
    @Binding var mode: YearViewMode

    var body: some View {
        ViewThatFits(in: .horizontal) {
            YearModeSegments(mode: $mode, showsTitles: true)
            YearModeSegments(mode: $mode, showsTitles: false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: .yearSegmentPicker))
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var mode = YearViewMode.calendar
        YearModePicker(mode: $mode)
            .whereBroadwayRoot()
    }
#endif
