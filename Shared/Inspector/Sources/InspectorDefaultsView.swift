import SwiftUI

struct InspectorDefaultsView: View {
    @State private var model: InspectorDefaultsModel
    @State private var searchText = ""

    init(domain: InspectorConfiguration.DefaultsDomain) {
        _model = State(initialValue: InspectorDefaultsModel(domain: domain))
    }

    var body: some View {
        List(filteredEntries) { entry in
            NavigationLink {
                InspectorDefaultEditorView(model: model, entry: entry)
            } label: {
                VStack(alignment: .leading) {
                    Text(entry.key)
                        .font(.body.monospaced())
                    Text(entry.value.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .navigationTitle(model.domain.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search defaults")
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    "No Defaults",
                    systemImage: "slider.horizontal.3",
                    description: Text("This persistent domain has no values."),
                )
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search
            }
        }
        .refreshable { model.reload() }
        .alert("UserDefaults Operation Failed", isPresented: $model.isPresentingError) {} message: {
            Text(model.errorMessage ?? "The operation failed.")
        }
    }

    private var filteredEntries: [InspectorDefaultEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.entries }
        return model.entries.filter {
            $0.key.localizedCaseInsensitiveContains(query)
                || $0.value.summary.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct InspectorDefaultEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let model: InspectorDefaultsModel
    let entry: InspectorDefaultEntry

    @State private var stringValue: String
    @State private var booleanValue: Bool
    @State private var integerValue: Int
    @State private var floatingPointValue: Double
    @State private var dateValue: Date
    @State private var isConfirmingDeletion = false
    @State private var validationMessage: String?
    @State private var isPresentingValidation = false

    init(model: InspectorDefaultsModel, entry: InspectorDefaultEntry) {
        self.model = model
        self.entry = entry
        switch entry.value {
            case let .string(value):
                _stringValue = State(initialValue: value)
            case let .url(value):
                _stringValue = State(initialValue: value.absoluteString)
            default:
                _stringValue = State(initialValue: "")
        }
        if case let .boolean(value) = entry.value {
            _booleanValue = State(initialValue: value)
        } else {
            _booleanValue = State(initialValue: false)
        }
        if case let .integer(value) = entry.value {
            _integerValue = State(initialValue: value)
        } else {
            _integerValue = State(initialValue: 0)
        }
        if case let .floatingPoint(value) = entry.value {
            _floatingPointValue = State(initialValue: value)
        } else {
            _floatingPointValue = State(initialValue: 0)
        }
        if case let .date(value) = entry.value {
            _dateValue = State(initialValue: value)
        } else {
            _dateValue = State(initialValue: Date())
        }
    }

    var body: some View {
        Form {
            Section("Key") {
                Text(entry.key)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            Section("Value") {
                editor
            }
            Section {
                Button("Delete Value", systemImage: "trash", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .confirmationDialog(
                    "Delete \(entry.key)?",
                    isPresented: $isConfirmingDeletion,
                    titleVisibility: .visible,
                ) {
                    Button("Delete Value", role: .destructive) {
                        if model.delete(key: entry.key) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .navigationTitle("User Default")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entry.value.isEditable {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .alert("Invalid Value", isPresented: $isPresentingValidation) {} message: {
            Text(validationMessage ?? "The value is invalid.")
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch entry.value {
            case .string:
                TextField("Value", text: $stringValue, axis: .vertical)
            case .boolean:
                Toggle("Value", isOn: $booleanValue)
            case .integer:
                TextField("Value", value: $integerValue, format: .number)
                    .keyboardType(.numbersAndPunctuation)
            case .floatingPoint:
                TextField("Value", value: $floatingPointValue, format: .number)
                    .keyboardType(.decimalPad)
            case .date:
                DatePicker("Value", selection: $dateValue)
            case .url:
                TextField("URL", text: $stringValue, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case let .complex(summary):
                LabeledContent("Read-only value", value: summary)
        }
    }

    private func save() {
        let value: InspectorDefaultValue
        switch entry.value {
            case .string:
                value = .string(stringValue)
            case .boolean:
                value = .boolean(booleanValue)
            case .integer:
                value = .integer(integerValue)
            case .floatingPoint:
                value = .floatingPoint(floatingPointValue)
            case .date:
                value = .date(dateValue)
            case .url:
                guard let url = URL(string: stringValue), url.scheme != nil else {
                    validationMessage = "Enter an absolute URL with a scheme."
                    isPresentingValidation = true
                    return
                }
                value = .url(url)
            case .complex:
                return
        }
        if model.save(value, forKey: entry.key) {
            dismiss()
        }
    }
}
