/// Declares labeled capture panels with ordinary Swift conditionals and loops.
/// Panel content remains lazy; the cutsheet validates the resulting identities.
@resultBuilder
public enum SnapshotPanelBuilder {
    public static func buildExpression(_ expression: SnapshotPanel) -> [SnapshotPanel] {
        [expression]
    }

    public static func buildBlock(_ components: [SnapshotPanel]...) -> [SnapshotPanel] {
        components.flatMap(\.self)
    }

    public static func buildArray(_ components: [[SnapshotPanel]]) -> [SnapshotPanel] {
        components.flatMap(\.self)
    }

    public static func buildOptional(_ component: [SnapshotPanel]?) -> [SnapshotPanel] {
        component ?? []
    }

    public static func buildEither(first component: [SnapshotPanel]) -> [SnapshotPanel] {
        component
    }

    public static func buildEither(second component: [SnapshotPanel]) -> [SnapshotPanel] {
        component
    }
}
