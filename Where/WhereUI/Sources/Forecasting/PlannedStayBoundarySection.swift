import SwiftUI

/// The same exact/flexible controls for arrival and inclusive departure.
struct PlannedStayBoundarySection: View {
    let title: String
    @Binding var boundary: PlannedStayEditorModel.Boundary

    var body: some View {
        Section(title) {
            Toggle(String(localized: .plannedStayEditorFlexibleDates), isOn: $boundary.isFlexible)
                .accessibilityLabel(String(localized: .plannedStayEditorBoundaryAccessibility(
                    title,
                    String(localized: .plannedStayEditorFlexibleDates),
                )))
            WhereDatePicker(
                String(localized: boundary.isFlexible
                    ? .plannedStayEditorEarliest
                    : .plannedStayEditorExactDate),
                selection: $boundary.earliest,
                accessibilityTitle: String(localized: .plannedStayEditorBoundaryAccessibility(
                    title,
                    String(localized: boundary.isFlexible
                        ? .plannedStayEditorEarliest
                        : .plannedStayEditorExactDate),
                )),
                displayedComponents: .date,
            )
            if boundary.isFlexible {
                WhereDatePicker(
                    String(localized: .plannedStayEditorLatest),
                    selection: $boundary.latest,
                    earliest: boundary.earliest,
                    accessibilityTitle: String(localized: .plannedStayEditorBoundaryAccessibility(
                        title,
                        String(localized: .plannedStayEditorLatest),
                    )),
                    displayedComponents: .date,
                )
            }
        }
    }
}

#if DEBUG
    #Preview {
        Form {
            PlannedStayBoundarySection(
                title: String(localized: .plannedStayEditorArrival),
                boundary: .constant(.init(date: PreviewSupport.referenceNow)),
            )
        }
        .whereBroadwayRoot()
    }
#endif
