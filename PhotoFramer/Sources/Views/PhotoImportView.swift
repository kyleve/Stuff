import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoImportView: View {
    @Bindable var viewModel: FramingViewModel

    @State private var selectedItem: PhotosPickerItem?
    @State private var showFilePicker = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Drag-and-drop zone
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                .frame(maxWidth: 400, minHeight: 180)
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Drop a photo here")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDrop(
                    of: [.image],
                    delegate: PhotoDropDelegate(
                        isTargeted: $isDropTargeted,
                        onDrop: { viewModel.importImage($0) }
                    )
                )

            Text("or")
                .foregroundStyle(.secondary)

            // Import buttons
            VStack(spacing: 12) {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images
                ) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose from Files", systemImage: "folder")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data),
                   let cgImage = uiImage.cgImage
                {
                    viewModel.importImage(cgImage)
                }
                selectedItem = nil
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url),
                   let uiImage = UIImage(data: data),
                   let cgImage = uiImage.cgImage
                {
                    viewModel.importImage(cgImage)
                }
            case .failure:
                break
            }
        }
    }
}
