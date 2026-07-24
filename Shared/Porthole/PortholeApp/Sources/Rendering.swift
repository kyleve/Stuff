import Foundation
import PortholeCore

/// Display helpers for `PortholeValue` in the app's tables and forms.
enum Rendering {
    /// A compact one-line cell string for a value.
    static func cell(_ value: PortholeValue?) -> String {
        guard let value else { return "" }
        switch value {
            case .null: return ""
            case let .bool(bool): return bool ? "true" : "false"
            case let .int(int): return String(int)
            case let .double(double): return String(double)
            case let .string(string): return string
            case let .data(data): return "<\(data.count) bytes>"
            case let .date(date): return date.formatted(date: .abbreviated, time: .standard)
            case .array, .object: return prettyJSON(value)
        }
    }

    /// The union of object-row keys across rows, in sorted order.
    static func columns(for rows: [PortholeValue]) -> [String] {
        var seen: Set<String> = []
        var columns: [String] = []
        for row in rows {
            guard case let .object(object) = row else { continue }
            for key in object.keys.sorted() where !seen.contains(key) {
                seen.insert(key)
                columns.append(key)
            }
        }
        return columns
    }

    /// Pretty-printed JSON for a value (fragments allowed, sorted keys).
    static func prettyJSON(_ value: PortholeValue) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: foundationObject(value),
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed],
        ), let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    private static func foundationObject(_ value: PortholeValue) -> Any {
        switch value {
            case .null: NSNull()
            case let .bool(bool): bool
            case let .int(int): int
            case let .double(double): double
            case let .string(string): string
            case let .data(data): ["$data": data.base64EncodedString()]
            case let .date(date): date.timeIntervalSince1970
            case let .array(array): array.map(foundationObject)
            case let .object(object): object.mapValues(foundationObject)
        }
    }
}
