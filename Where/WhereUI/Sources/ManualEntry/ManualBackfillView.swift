import SwiftUI
import WhereCore

struct ManualBackfillView: View {
    @Environment(\.dismiss) private var dismiss

    private let onPreview: (ManualImportBackfillRequest) -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var jurisdiction: TaxJurisdiction
    @State private var note: String
    @State private var kind: ManualLogEntry.Kind
    @State private var evidenceFiles: [URL]
    @State private var isPickingEvidence = false

    init(
        initialDate: Date,
        onPreview: @escaping (ManualImportBackfillRequest) -> Void,
    ) {
        self.onPreview = onPreview
        _startDate = State(initialValue: initialDate)
        _endDate = State(initialValue: initialDate)
        _jurisdiction = State(initialValue: .california)
        _note = State(initialValue: "")
        _kind = State(initialValue: .supplemental)
        _evidenceFiles = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }

                Section("Details") {
                    Picker("Kind", selection: $kind) {
                        Text("Supplemental").tag(ManualLogEntry.Kind.supplemental)
                        Text("Correction").tag(ManualLogEntry.Kind.correction)
                    }
                    .pickerStyle(.segmented)

                    Picker("Jurisdiction", selection: $jurisdiction) {
                        ForEach(jurisdictionOptions, id: \.self) { option in
                            Text(option.displayName)
                                .tag(option)
                        }
                    }

                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3 ... 6)
                }

                Section("Shared Evidence") {
                    if evidenceFiles.isEmpty {
                        Text("Optional files that should be attached to every created day.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(evidenceFiles, id: \.self) { fileURL in
                            Text(fileURL.lastPathComponent)
                                .font(.footnote)
                        }
                        .onDelete { offsets in
                            evidenceFiles.remove(atOffsets: offsets)
                        }
                    }

                    Button("Add Evidence Files") {
                        isPickingEvidence = true
                    }
                }
            }
            .navigationTitle("Backfill Days")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Preview Import") {
                        onPreview(
                            ManualImportBackfillRequest(
                                startDate: startDate,
                                endDate: endDate,
                                jurisdiction: jurisdiction,
                                note: note,
                                kind: kind,
                                evidenceFiles: evidenceFiles,
                            ),
                        )
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingEvidence,
            allowedContentTypes: [.content, .data, .image, .pdf],
            allowsMultipleSelection: true,
        ) { result in
            guard case let .success(urls) = result else {
                return
            }

            evidenceFiles = urls.compactMap(stageEvidenceFile).sorted {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }
        }
    }

    private var jurisdictionOptions: [TaxJurisdiction] {
        let preferredStates: [TaxJurisdiction] = [.california, .newYork, .unknown]
        let remainingStates = USState.allCases
            .map(TaxJurisdiction.state)
            .filter { !preferredStates.contains($0) }
            .sorted { $0.displayName < $1.displayName }

        return preferredStates + remainingStates
    }

    private func stageEvidenceFile(_ fileURL: URL) -> URL? {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory.appending(path: "WhereBackfillEvidence")
        let stagedURL = directory.appending(path: "\(UUID().uuidString)-\(fileURL.lastPathComponent)")

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil,
            )
            try data.write(to: stagedURL, options: .atomic)
            return stagedURL
        } catch {
            return nil
        }
    }
}
