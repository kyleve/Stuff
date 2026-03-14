import SwiftUI

struct FramingEditorView: View {
    @Bindable var viewModel: FramingViewModel

    @State private var showExportSheet = false
    @State private var showFileExporter = false
    @State private var exportDocument: FramedImageDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live preview
                if let preview = viewModel.framedPreview {
                    Image(decorative: preview, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 4)
                        .padding(.horizontal)
                }

                // Framing mode picker
                Picker("Mode", selection: $viewModel.configuration.mode) {
                    ForEach(FramingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                // Frame size picker
                FrameSizePicker(selection: $viewModel.configuration.frameSize)

                // Mat color (only when fitWithMat)
                if viewModel.configuration.mode == .fitWithMat {
                    MatColorPicker(color: $viewModel.configuration.matColor)
                }
            }
            .padding(.vertical)
        }
        .onChange(of: viewModel.configuration.mode) { _, _ in viewModel.updatePreview() }
        .onChange(of: viewModel.configuration.frameSize) { _, _ in viewModel.updatePreview() }
        .onChange(of: viewModel.configuration.matColor) { _, _ in viewModel.updatePreview() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Start Over") {
                    viewModel.reset()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(viewModel: viewModel)
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentType: .png,
            defaultFilename: "framed-photo.png"
        ) { _ in
            exportDocument = nil
        }
    }
}
