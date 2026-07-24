import Foundation
import PortholeClientKit
import PortholeCore

/// Backs a schema-generated form for one action: it holds an editable field per
/// top-level parameter, invokes the action, and exposes the result.
@MainActor
@Observable
final class ActionFormModel {
    let descriptor: PortholeActionDescriptor
    private let ref: PortholeActionRef
    private let session: PortholeSession

    /// One editable field per top-level object property.
    struct Field: Identifiable {
        let id: String
        let kind: PortholeSchema.Kind
        var stringValue: String = ""
        var boolValue: Bool = false
    }

    var fields: [Field]
    /// Free-form JSON editor, used when the parameters aren't a flat object.
    var rawJSON = "{}"
    var usesRawEditor: Bool
    private(set) var resultText: String?
    private(set) var errorMessage: String?
    private(set) var isRunning = false

    init(
        descriptor: PortholeActionDescriptor,
        connector: PortholeConnectorID,
        session: PortholeSession,
    ) {
        self.descriptor = descriptor
        ref = PortholeActionRef(connector: connector, action: descriptor.id)
        self.session = session

        if descriptor.parameters.kind == .object,
           let properties = descriptor.parameters.properties
        {
            fields = properties
                .sorted { $0.key < $1.key }
                .map { Field(id: $0.key, kind: $0.value.kind) }
            usesRawEditor = false
        } else {
            fields = []
            usesRawEditor = true
        }
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        do {
            let parameters = try buildParameters()
            let result = try await session.invoke(ref, parameters: parameters)
            resultText = Rendering.prettyJSON(result)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func buildParameters() throws -> PortholeValue {
        if usesRawEditor {
            guard let data = rawJSON.data(using: .utf8) else { return .object([:]) }
            return try JSONDecoder().decode(PortholeValue.self, from: data)
        }
        var object: [String: PortholeValue] = [:]
        for field in fields {
            switch field.kind {
                case .boolean:
                    object[field.id] = .bool(field.boolValue)
                case .integer:
                    if let int = Int64(field.stringValue) { object[field.id] = .int(int) }
                case .number:
                    if let double = Double(field.stringValue) { object[field.id] = .double(double) }
                case .string, .data, .date, .array, .object:
                    if !field.stringValue.isEmpty { object[field.id] = .string(field.stringValue) }
            }
        }
        return .object(object)
    }
}
