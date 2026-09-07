import SwiftUI

/// Searchable editor for the FlaggerModel injected into the view environment.
public struct FlaggerEditorView: View {
    @Environment(FlaggerModel.self) private var model

    public init() {}

    public var body: some View {
        @Bindable var model = model
        NavigationStack {
            FlaggerEditorList(model: model)
                .navigationTitle("Feature Flags")
        }
    }
}
