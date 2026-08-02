#if DEBUG
    import CoreFoundation
    import Foundation

    /// Computes a leaf-level difference between a designer configuration and
    /// the app defaults for sparse JSON and paste-ready Swift exports.
    enum CardDesignerConfigurationDifference {
        static func jsonObject(
            for configuration: CardDesignerConfiguration,
        ) throws -> [String: Any] {
            let current = try object(for: configuration)
            let standard = try object(for: .standard)
            var difference = difference(current, from: standard) as? [String: Any] ?? [:]
            // Schema metadata describes the sparse payload rather than a style
            // change, so retain it even though it matches the baseline.
            difference["schemaVersion"] = configuration.schemaVersion
            return difference
        }

        static func swiftAssignments(
            for configuration: CardDesignerConfiguration,
        ) throws -> [String] {
            let current = try object(for: configuration)
            let standard = try object(for: .standard)
            guard let difference = difference(current, from: standard) as? [String: Any]
            else { return [] }

            var assignments: [String] = []
            appendAssignments(
                from: difference,
                path: "configuration",
                to: &assignments,
            )
            return assignments
        }

        private static func object(
            for configuration: CardDesignerConfiguration,
        ) throws -> [String: Any] {
            let data = try JSONEncoder().encode(configuration)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw DifferenceError.invalidConfigurationObject
            }
            return object
        }

        private static func difference(_ current: Any, from standard: Any?) -> Any? {
            if
                let current = current as? [String: Any],
                let standard = standard as? [String: Any]
            {
                var result: [String: Any] = [:]
                for key in current.keys.sorted() {
                    guard let currentValue = current[key] else { continue }
                    if let value = difference(currentValue, from: standard[key]) {
                        result[key] = value
                    }
                }
                return result.isEmpty ? nil : result
            }

            guard let standard else { return current }
            return valuesAreEqual(current, standard) ? nil : current
        }

        private static func valuesAreEqual(_ lhs: Any, _ rhs: Any) -> Bool {
            guard let lhs = lhs as? NSObject, let rhs = rhs as? NSObject else { return false }
            return lhs.isEqual(rhs)
        }

        private static func appendAssignments(
            from difference: [String: Any],
            path: String,
            to assignments: inout [String],
        ) {
            for key in difference.keys.sorted() where key != "schemaVersion" {
                let nextPath = "\(path).\(key)"
                if let nested = difference[key] as? [String: Any] {
                    appendAssignments(from: nested, path: nextPath, to: &assignments)
                } else if let value = difference[key] {
                    assignments.append("\(nextPath) = \(swiftLiteral(value))")
                }
            }
        }

        private static func swiftLiteral(_ value: Any) -> String {
            if let number = value as? NSNumber {
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    return number.boolValue ? "true" : "false"
                }
                return number.stringValue
            }
            if let rawValue = value as? String {
                // Every string in CardDesignerConfiguration is a RawRepresentable
                // enum case, so member syntax is both compact and compilable.
                return ".\(rawValue)"
            }
            assertionFailure("Unsupported card designer export value: \(value)")
            return "/* unsupported */"
        }

        private enum DifferenceError: Error {
            case invalidConfigurationObject
        }
    }
#endif
