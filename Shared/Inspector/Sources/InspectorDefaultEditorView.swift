import SFSafeSymbols
import SwiftUI

struct InspectorDefaultEditorView: View {
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
                InspectorDefaultValueFields(
                    value: entry.value,
                    stringValue: $stringValue,
                    booleanValue: $booleanValue,
                    integerValue: $integerValue,
                    floatingPointValue: $floatingPointValue,
                    dateValue: $dateValue,
                )
            }
            Section {
                InspectorDeleteButton(
                    title: "Delete Value",
                    symbol: .trash,
                    question: "Delete \(entry.key)?",
                    isConfirming: $isConfirmingDeletion,
                ) {
                    if model.delete(key: entry.key) {
                        dismiss()
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

#if DEBUG
    #Preview {
        NavigationStack {
            InspectorDefaultEditorView(
                model: InspectorDefaultsModel(domain: InspectorPreviewData.defaultsDomain),
                entry: .init(key: "Show Details", value: .boolean(true)),
            )
        }
    }
#endif
