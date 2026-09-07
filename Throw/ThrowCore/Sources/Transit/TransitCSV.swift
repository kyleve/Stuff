import Foundation

struct TransitCSV {
    private let header: [String: Int]
    private let rows: [[String]]

    init(data: Data) throws {
        let parsed = try Self.parse(data)
        guard let names = parsed.first, names.isEmpty == false else {
            throw TransitDataError.invalidSchedule
        }
        let normalizedNames = names.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard Set(normalizedNames).count == normalizedNames.count else {
            throw TransitDataError.invalidSchedule
        }
        header = Dictionary(uniqueKeysWithValues: normalizedNames.enumerated().map { ($1, $0) })
        rows = parsed.dropFirst().filter { row in
            row.contains { $0.isEmpty == false }
        }
    }

    func values() throws -> [[String: String]] {
        try rows.map { row in
            guard row.count == header.count else { throw TransitDataError.invalidSchedule }
            return header.reduce(into: [String: String]()) { result, item in
                result[item.key] = row[item.value]
            }
        }
    }

    private static func parse(_ data: Data) throws -> [[String]] {
        enum State {
            case unquoted
            case quoted
            case quoteClosed
        }

        var result: [[String]] = []
        var row: [String] = []
        var field: [UInt8] = []
        var state = State.unquoted
        let bytes = Array(data)
        var index = 0

        func decodedField() throws -> String {
            guard let value = String(bytes: field, encoding: .utf8) else {
                throw TransitDataError.invalidSchedule
            }
            return value
        }

        while index < bytes.count {
            let byte = bytes[index]
            switch (state, byte) {
                case (.unquoted, 0x22):
                    guard field.isEmpty else { throw TransitDataError.invalidSchedule }
                    state = .quoted
                case (.unquoted, 0x2C), (.quoteClosed, 0x2C):
                    try row.append(decodedField())
                    field = []
                    state = .unquoted
                case (.unquoted, 0x0A), (.quoteClosed, 0x0A):
                    try row.append(decodedField())
                    result.append(row)
                    row = []
                    field = []
                    state = .unquoted
                case (.unquoted, 0x0D), (.quoteClosed, 0x0D):
                    try row.append(decodedField())
                    result.append(row)
                    row = []
                    field = []
                    state = .unquoted
                    if index + 1 < bytes.count, bytes[index + 1] == 0x0A { index += 1 }
                case (.quoted, 0x22):
                    state = .quoteClosed
                case (.quoteClosed, 0x22):
                    field.append(0x22)
                    state = .quoted
                case (.quoteClosed, _):
                    throw TransitDataError.invalidSchedule
                case (.unquoted, _), (.quoted, _):
                    field.append(byte)
            }
            index += 1
        }
        guard state != .quoted else { throw TransitDataError.invalidSchedule }
        if field.isEmpty == false || row.isEmpty == false {
            try row.append(decodedField())
            result.append(row)
        }
        return result
    }
}
