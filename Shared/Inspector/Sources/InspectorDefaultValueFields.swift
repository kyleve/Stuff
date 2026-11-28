import SFSafeSymbols
import SwiftUI

struct InspectorDefaultValueFields: View {
    let value: InspectorDefaultValue
    @Binding var stringValue: String
    @Binding var booleanValue: Bool
    @Binding var integerValue: Int
    @Binding var floatingPointValue: Double
    @Binding var dateValue: Date

    var body: some View {
        switch value {
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
