import Foundation
import PortholeCore

/// Renders Porthole values for the terminal: pretty JSON, or an aligned table of
/// object rows. Pure functions so they're unit-tested without a device.
public enum OutputFormatting {
    /// Pretty-prints a value as JSON (sorted keys). `.data` becomes a
    /// `{"$data": …}` marker; `.date` becomes an ISO-8601 string.
    public static func json(_ value: PortholeValue) -> String {
        let object = foundationObject(value)
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed],
        ), let string = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return string
    }

    /// Renders `.object` rows as an aligned column table; falls back to JSON for
    /// non-object rows. Columns are the union of keys across rows, in first-seen
    /// order.
    public static func table(_ rows: [PortholeValue]) -> String {
        guard !rows.isEmpty else { return "(no rows)" }
        var columns: [String] = []
        var seen: Set<String> = []
        for row in rows {
            guard case let .object(object) = row
            else { return rows.map(json).joined(separator: "\n") }
            for key in object.keys.sorted() where !seen.contains(key) {
                seen.insert(key)
                columns.append(key)
            }
        }

        let cells: [[String]] = rows.map { row in
            guard case let .object(object) = row else { return columns.map { _ in "" } }
            return columns.map { cellString(object[$0]) }
        }

        var widths = columns.map(\.count)
        for row in cells {
            for (index, cell) in row.enumerated() {
                widths[index] = max(widths[index], cell.count)
            }
        }

        func pad(_ string: String, _ width: Int) -> String {
            string + String(repeating: " ", count: max(0, width - string.count))
        }

        var lines: [String] = []
        lines.append(zip(columns, widths).map { pad($0, $1) }.joined(separator: "  "))
        lines.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        for row in cells {
            lines.append(zip(row, widths).map { pad($0, $1) }.joined(separator: "  "))
        }
        return lines.joined(separator: "\n")
    }

    static func cellString(_ value: PortholeValue?) -> String {
        guard let value else { return "" }
        switch value {
            case .null: return ""
            case let .bool(bool): return bool ? "true" : "false"
            case let .int(int): return String(int)
            case let .double(double): return String(double)
            case let .string(string): return string
            case let .data(data): return "<\(data.count) bytes>"
            case let .date(date): return PortholeISO8601Display.string(from: date)
            case .array, .object: return compactJSON(value)
        }
    }

    private static func compactJSON(_ value: PortholeValue) -> String {
        let object = foundationObject(value)
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed],
        ),
            let string = String(data: data, encoding: .utf8)
        else { return String(describing: value) }
        return string
    }

    static func foundationObject(_ value: PortholeValue) -> Any {
        switch value {
            case .null: NSNull()
            case let .bool(bool): bool
            case let .int(int): int
            case let .double(double): double
            case let .string(string): string
            case let .data(data): ["$data": data.base64EncodedString()]
            case let .date(date): PortholeISO8601Display.string(from: date)
            case let .array(array): array.map { foundationObject($0) }
            case let .object(object): object.mapValues { foundationObject($0) }
        }
    }
}

enum PortholeISO8601Display {
    private nonisolated(unsafe) static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
