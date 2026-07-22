import SwiftUI
import WhereCore

/// Your Data tab: the selected year's attachments and hand-logged days, toggled
/// by a segmented control (remembered across launches by
/// ``SegmentedTabContainer``). Each segment's content view carries its own
/// contextual "+" toolbar item, so the bar follows the active segment.
struct YourDataView: View {
    let report: YearReportModel

    var body: some View {
        NavigationStack {
            SegmentedTabContainer(
                storageKey: .data,
                initialSelection: DataSegment.attachments,
                pickerLabel: Strings.dataSegmentPickerLabel,
            ) { segment in
                switch segment {
                    case .attachments:
                        EvidenceListView(report: report)
                    case .loggedDays:
                        LoggedDaysView(report: report)
                }
            }
            .navigationTitle(Strings.tabData)
        }
    }
}

/// The Your Data tab's two archives for the selected year.
enum DataSegment: String, CaseIterable, SegmentedItem {
    case attachments
    case loggedDays

    var title: String {
        switch self {
            case .attachments: Strings.dataSegmentAttachments
            case .loggedDays: Strings.primaryLoggedDays
        }
    }
}

#if DEBUG
    #Preview {
        YourDataView(report: PreviewSupport.loadedYearReportModel())
    }
#endif
