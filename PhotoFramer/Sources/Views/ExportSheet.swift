import SwiftUI

struct ExportSheet: View {
    @Bindable var viewModel: FramingViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showFileExporter = false
    @State private var exportDocument: FramedImageDocument?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if viewModel.isExporting {
                    ProgressView("Exporting…")
                        .padding()
                } else if viewModel.showExportSuccess {
                    Label("Saved to Photo Library", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding()

                    Button("Done") {
                        viewModel.showExportSuccess = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    VStack(spacing: 12) {
                        Button {
                            Task {
                                await viewModel.exportToPhotoLibrary()
                            }
                        } label: {
                            Label("Save to Photo Library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            exportDocument = viewModel.framedImageForFileExport()
                            showFileExporter = true
                        } label: {
                            Label("Save to Files", systemImage: "folder")
                                .frame(maxWidth: 280)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if let error = viewModel.exportError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .padding()
            .navigationTitle("Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $showFileExporter,
                document: exportDocument,
                contentType: .png,
                defaultFilename: "framed-photo.png"
            ) { result in
                exportDocument = nil
                if case .success = result {
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }
}
