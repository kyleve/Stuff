import RegionKit
import SwiftUI
import WhereCore

/// Shared sheet routes for itinerary management and individual stay editing.
enum PlannedStaysDestination: Hashable, Identifiable {
    case list
    case new(Region)
    case edit(PlannedStay)

    var id: Self {
        self
    }
}

struct PlannedStaysDestinationView: View {
    let destination: PlannedStaysDestination
    let report: YearReportModel

    var body: some View {
        switch destination {
            case .list:
                PlannedStaysView(report: report)
            case let .new(region):
                PlannedStayEditor(report: report, initialRegion: region)
            case let .edit(stay):
                PlannedStayEditor(report: report, stay: stay)
        }
    }
}

#if DEBUG
    #Preview {
        PlannedStaysDestinationView(
            destination: .list,
            report: PreviewSupport.plannedStayYearReportModel(),
        )
    }
#endif
