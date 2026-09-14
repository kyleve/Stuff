import Foundation
import PortholeCore

extension PortholeCapability {
    /// Match the same descriptive fields in local and remote capability lists.
    func matches(search: String) -> Bool {
        guard !search.isEmpty else { return true }
        var fields = [name, module.rawValue, summary, id.rawValue]
        fields.append(contentsOf: parameters.flatMap { [$0.name, $0.summary] })
        if case let .unsupported(reason) = availability { fields.append(reason) }
        return fields.contains { $0.localizedStandardContains(search) }
    }
}
