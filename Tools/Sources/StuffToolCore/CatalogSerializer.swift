import Foundation

/// Serializes a parsed String Catalog byte-for-byte the way Xcode does.
public struct CatalogSerializer: Sendable {
    public enum Failure: Error, CustomStringConvertible {
        case unsupportedValue(String)

        public var description: String {
            switch self {
                case let .unsupportedValue(valueDescription):
                    "unsupported JSON value in catalog: \(valueDescription)"
            }
        }
    }

    public init() {}

    public func data(from object: Any) throws -> Data {
        var output = ""
        try write(object, indent: 0, into: &output)
        return Data(output.utf8)
    }

    private func write(_ value: Any, indent: Int, into output: inout String) throws {
        switch value {
            case let dictionary as [String: Any]:
                try write(dictionary: dictionary, indent: indent, into: &output)
            case let array as [Any]:
                try write(array: array, indent: indent, into: &output)
            default:
                output += try fragment(for: value)
        }
    }

    private func write(
        dictionary: [String: Any],
        indent: Int,
        into output: inout String,
    ) throws {
        guard dictionary.isEmpty == false else {
            output += "{\n\n\(pad(indent))}"
            return
        }
        output += "{\n"
        let keys = dictionary.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        for (offset, key) in keys.enumerated() {
            try output += "\(pad(indent + 1))\(fragment(for: key)) : "
            try write(dictionary[key]!, indent: indent + 1, into: &output)
            output += offset == keys.count - 1 ? "\n" : ",\n"
        }
        output += "\(pad(indent))}"
    }

    private func write(array: [Any], indent: Int, into output: inout String) throws {
        guard array.isEmpty == false else {
            output += "[\n\n\(pad(indent))]"
            return
        }
        output += "[\n"
        for (offset, element) in array.enumerated() {
            output += pad(indent + 1)
            try write(element, indent: indent + 1, into: &output)
            output += offset == array.count - 1 ? "\n" : ",\n"
        }
        output += "\(pad(indent))]"
    }

    private func fragment(for value: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject([value]) else {
            throw Failure.unsupportedValue("\(type(of: value)) (\(value))")
        }
        let data = try JSONSerialization.data(
            withJSONObject: [value],
            options: [.withoutEscapingSlashes],
        )
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }

    private func pad(_ indent: Int) -> String {
        String(repeating: "  ", count: indent)
    }
}
