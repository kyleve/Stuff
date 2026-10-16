import SwiftUI

/// Attach to a stable owner, above any container that changes during resizing.
struct PlanningPresentation: ViewModifier {
    let report: YearReportModel
    @Bindable var navigation: PlanningPresentationModel
    var isEnabled = true

    func body(content: Content) -> some View {
        if isEnabled {
            content.sheet(item: $navigation.destination) { destination in
                PlannedStaysDestinationView(destination: destination, report: report)
            }
        } else {
            content
        }
    }
}
