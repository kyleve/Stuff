import SwiftUI

struct FlaggerEditorList: View {
    @Bindable var model: FlaggerModel

    var body: some View {
        List {
            ForEach(model.filteredSources) { source in
                Section(source.name) {
                    ForEach(source.groups) { group in
                        Text(group.name)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(group.flags) { flag in
                            FlaggerEditorRow(flag: flag, model: model)
                        }
                    }
                }
            }
        }
        .searchable(text: $model.searchText, prompt: "Source, group, name, or ID")
        .overlay {
            if model.filteredFlags.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .alert(
            "Couldn’t Update Flag",
            isPresented: $model.isPresentingError,
            presenting: model.error,
        ) { _ in
            Button("OK", role: .cancel, action: model.dismissError)
        } message: { error in
            Text(error.localizedDescription)
        }
    }
}

extension FlaggerModel {
    fileprivate var isPresentingError: Bool {
        get { error != nil }
        set { if newValue == false { dismissError() } }
    }
}
