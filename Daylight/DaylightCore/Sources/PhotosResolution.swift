/// Retrying an uncertain save requires the user to check Photos for the original first.
public enum PhotosResolution: Sendable {
    case retry
    case confirmedAbsent
}
