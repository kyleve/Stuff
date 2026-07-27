/// A result builder so a ``SnapshotProviding`` can declare its `snapshots` as a
/// sequence of ``SnapshotCase`` values (with `if`/`for` support) instead of an
/// explicit array literal.
@resultBuilder
public enum SnapshotCaseBuilder {
    public static func buildExpression(_ expression: SnapshotCase) -> [SnapshotCase] {
        [expression]
    }

    public static func buildExpression(_ expression: [SnapshotCase]) -> [SnapshotCase] {
        expression
    }

    public static func buildBlock(_ components: [SnapshotCase]...) -> [SnapshotCase] {
        components.flatMap(\.self)
    }

    public static func buildArray(_ components: [[SnapshotCase]]) -> [SnapshotCase] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [SnapshotCase]?) -> [SnapshotCase] {
        component ?? []
    }

    public static func buildEither(first component: [SnapshotCase]) -> [SnapshotCase] {
        component
    }

    public static func buildEither(second component: [SnapshotCase]) -> [SnapshotCase] {
        component
    }
}
