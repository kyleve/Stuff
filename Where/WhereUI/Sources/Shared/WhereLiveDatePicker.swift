import SwiftUI

struct WhereLiveDatePicker: View {
    let title: String
    @Binding var selection: Date
    let earliest: Date?
    let latest: Date?
    let displayedComponents: DatePickerComponents

    var body: some View {
        if let earliest, let latest {
            DatePicker(
                title,
                selection: $selection,
                in: earliest ... latest,
                displayedComponents: displayedComponents,
            )
        } else if let latest {
            DatePicker(
                title,
                selection: $selection,
                in: ...latest,
                displayedComponents: displayedComponents,
            )
        } else if let earliest {
            DatePicker(
                title,
                selection: $selection,
                in: earliest...,
                displayedComponents: displayedComponents,
            )
        } else {
            DatePicker(title, selection: $selection, displayedComponents: displayedComponents)
        }
    }
}

#if DEBUG
    #Preview { WhereLiveDatePicker(
        title: "Day",
        selection: .constant(PreviewSupport.referenceNow),
        earliest: nil,
        latest: nil,
        displayedComponents: .date,
    ) }
#endif
