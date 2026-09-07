/// Credential workflow state; it intentionally never contains the saved secret.
public enum CredentialEditorState: Equatable, Sendable {
    case missing
    case saved(lastFour: String?)
    case editing
    case testing
    case testSucceeded(lastFour: String?)
    case testFailed(ThrowFailureCategory)
}
