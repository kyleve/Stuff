/// Author-approved export eligibility and the controls that must all be enabled.
/// These requirements describe a schema, not an inspection of the field's contents.
public enum LogExportRequirements: Equatable, Sendable {
    case baseline(requiring: Set<LogExportControl>)
    case diagnostic(requiring: Set<LogExportControl>)
    case never

    /// A child cannot weaken its parent's eligibility or remove a required control.
    public func constrained(by parent: Self) -> Self {
        switch (self, parent) {
            case (.never, _), (_, .never):
                .never
            case let (.baseline(child), .baseline(parent)):
                .baseline(requiring: child.union(parent))
            case let (.baseline(child), .diagnostic(parent)),
                 let (.diagnostic(child), .baseline(parent)),
                 let (.diagnostic(child), .diagnostic(parent)):
                .diagnostic(requiring: child.union(parent))
        }
    }
}
