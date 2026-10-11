/// Compiler-checked value projections used by generated events.
/// Optional promotion lets aliases and all Swift optional spellings use the same checks.
public enum LogFieldProjection {
    public static func boolean(_ value: Bool?, key: LogFieldKey) -> ClassifiedLogField? {
        value.map { value in .shareable(key: key, kind: .boolean, value: .bool(value)) }
    }

    public static func count(_ value: Int?, key: LogFieldKey) -> ClassifiedLogField? {
        value.map { value in .shareable(key: key, kind: .count, value: .int(value)) }
    }

    public static func limit(_ value: Int?, key: LogFieldKey) -> ClassifiedLogField? {
        value.map { value in .shareable(key: key, kind: .limit, value: .int(value)) }
    }

    public static func duration(_ value: Duration?, key: LogFieldKey) -> ClassifiedLogField? {
        value.map { value in .shareable(
            key: key,
            kind: .duration,
            value: .double(value.periscopeMilliseconds),
        ) }
    }

    public static func json(_ value: JSONValue?, key: LogFieldKey) -> ClassifiedLogField? {
        value.map { value in .shareable(key: key, kind: .json, value: .json(value)) }
    }

    public static func category<Category>(
        _ value: Category?,
        key: LogFieldKey,
    ) -> ClassifiedLogField?
        where Category: Codable & Sendable & CaseIterable & RawRepresentable,
        Category.RawValue == String
    {
        guard let value else { return nil }
        // Decoding and mutation can bypass classified input construction.
        precondition(
            isClosedLogCategory(value),
            "Shareable log categories must be members of a closed CaseIterable set",
        )
        return .shareable(key: key, kind: .category, value: .string(value.rawValue))
    }

    public static func categoryExport<Category>(
        _ value: Category,
        key: LogFieldKey,
    ) -> LogExportField
        where Category: Codable & Sendable & CaseIterable & RawRepresentable,
        Category.RawValue == String
    {
        LogExportField(
            key,
            description: .category(
                value,
                allowedValues: Set(Category.allCases
                    .map(\.rawValue)),
                allowsNil: false,
            ),
            requirements: .baseline(requiring: []),
        )
    }

    public static func categoryExport<Category>(
        _ value: Category?,
        key: LogFieldKey,
    ) -> LogExportField
        where Category: Codable & Sendable & CaseIterable & RawRepresentable,
        Category.RawValue == String
    {
        LogExportField(
            key,
            description: .category(
                value,
                allowedValues: Set(Category.allCases
                    .map(\.rawValue)),
                allowsNil: true,
            ),
            requirements: .baseline(requiring: []),
        )
    }
}
