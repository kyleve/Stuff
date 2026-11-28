import SwiftUI

struct FlyoverOptionsPicker<Choice: Hashable & Identifiable>: View {
    let title: LocalizedStringKey
    let choices: [Choice]
    @Binding var selection: Choice
    let label: KeyPath<Choice, String>

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices) { choice in
                Text(choice[keyPath: label]).tag(choice)
            }
        }
    }
}

#if DEBUG
    #Preview {
        FlyoverView(catalog: FlyoverPreview.catalog)
    }
#endif
