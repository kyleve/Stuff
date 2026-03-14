import SwiftUI

struct ContentView: View {
    @State private var viewModel = FramingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.importedPhoto == nil {
                    PhotoImportView(viewModel: viewModel)
                } else {
                    FramingEditorView(viewModel: viewModel)
                }
            }
            .navigationTitle("Photo Framer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
