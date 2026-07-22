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
            .navigationTitle(navigationTitle)
        }
    }

    /// Plain "Your Data" for the current year; suffixed with the year when
    /// viewing a past one, so the year in view is never ambiguous.
    private var navigationTitle: String {
        report.selectedYear == WhereModel.currentYear
            ? Strings.tabData
            : Strings.tabDataTitle(forYear: report.selectedYear)
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
