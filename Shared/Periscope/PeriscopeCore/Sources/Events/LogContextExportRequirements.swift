/// Permissions for context outside the classified event payload.
/// Adapters choose their output fields but share these rules, independent of UI control groups.
public enum LogContextExportRequirements {
    public static let externalID = LogExportRequirements.diagnostic(requiring: [.identifiers])
    public static let sessionID = LogExportRequirements.diagnostic(requiring: [.identifiers])
    public static let spanID = LogExportRequirements.diagnostic(requiring: [.identifiers])
    public static let date = LogExportRequirements.diagnostic(requiring: [.personalData])
    public static let sessionDetails = LogExportRequirements.diagnostic(requiring: [.personalData])

    public static let tags = unclassifiedContext
    public static let scopes = unclassifiedContext
    public static let sessionAttributes = unclassifiedContext
    public static let attachmentMetadata = unclassifiedContext

    private static let unclassifiedContext = LogExportRequirements.diagnostic(
        requiring: [.identifiers, .location, .userContent, .personalData],
    )
}
