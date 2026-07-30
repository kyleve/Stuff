import CoreFoundation
import Foundation
import Observation

struct InspectorDefaultEntry: Identifiable, Hashable {
    let key: String
    let value: InspectorDefaultValue

    var id: String {
        key
    }
}

enum InspectorDefaultValue: Hashable {
    case string(String)
    case boolean(Bool)
    case integer(Int)
    case floatingPoint(Double)
    case date(Date)
    case url(URL)
    case complex(summary: String)

    init(
        persistentValue value: Any,
        userDefaults: UserDefaults,
        key: String,
    ) {
        switch value {
            case let value as Bool:
                self = .boolean(value)
            case let value as NSNumber
            where CFGetTypeID(value) == CFBooleanGetTypeID():
                self = .boolean(value.boolValue)
            case let value as Int:
                self = .integer(value)
            case let value as NSNumber:
                let type = String(cString: value.objCType)
                self = type.contains(".") || type == "f" || type == "d"
                    ? .floatingPoint(value.doubleValue)
                    : .integer(value.intValue)
            case let value as Double:
                self = .floatingPoint(value)
            case let value as Date:
                self = .date(value)
            case let value as URL:
                self = .url(value)
            case let value as String:
                self = .string(value)
            case let value as Data:
                if let url = userDefaults.url(forKey: key) {
                    self = .url(url)
                } else {
                    self = .complex(summary: "\(value.count) bytes")
                }
            case let value as [Any]:
                self = .complex(summary: "Array (\(value.count) values)")
            case let value as [String: Any]:
                self = .complex(summary: "Dictionary (\(value.count) values)")
            default:
                self = .complex(summary: String(describing: value))
        }
    }

    var summary: String {
        switch self {
            case let .string(value): value
            case let .boolean(value): value ? "true" : "false"
            case let .integer(value): value.formatted()
            case let .floatingPoint(value): value.formatted()
            case let .date(value): value.formatted(date: .numeric, time: .standard)
            case let .url(value): value.absoluteString
            case let .complex(summary): summary
        }
    }

    var isEditable: Bool {
        if case .complex = self {
            return false
        }
        return true
    }
}

@MainActor
@Observable
final class InspectorDefaultsModel {
    let domain: InspectorConfiguration.DefaultsDomain
    private(set) var entries: [InspectorDefaultEntry] = []
    private(set) var errorMessage: String?

    init(domain: InspectorConfiguration.DefaultsDomain) {
        self.domain = domain
        reload()
    }

    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    func reload() {
        let values = domain.userDefaults
            .persistentDomain(forName: domain.persistentDomainName) ?? [:]
        entries = values
            .map {
                InspectorDefaultEntry(
                    key: $0.key,
                    value: InspectorDefaultValue(
                        persistentValue: $0.value,
                        userDefaults: domain.userDefaults,
                        key: $0.key,
                    ),
                )
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    func save(_ value: InspectorDefaultValue, forKey key: String) -> Bool {
        switch value {
            case let .string(value):
                domain.userDefaults.set(value, forKey: key)
            case let .boolean(value):
                domain.userDefaults.set(value, forKey: key)
            case let .integer(value):
                domain.userDefaults.set(value, forKey: key)
            case let .floatingPoint(value):
                domain.userDefaults.set(value, forKey: key)
            case let .date(value):
                domain.userDefaults.set(value, forKey: key)
            case let .url(value):
                domain.userDefaults.set(value, forKey: key)
            case .complex:
                errorMessage = "This value type is read-only."
                return false
        }
        reload()
        guard entries.first(where: { $0.key == key })?.value == value else {
            errorMessage = "UserDefaults did not retain the updated value and type."
            return false
        }
        errorMessage = nil
        return true
    }

    func delete(key: String) -> Bool {
        domain.userDefaults.removeObject(forKey: key)
        reload()
        guard !entries.contains(where: { $0.key == key }) else {
            errorMessage = "UserDefaults did not remove the value."
            return false
        }
        errorMessage = nil
        return true
    }
}
