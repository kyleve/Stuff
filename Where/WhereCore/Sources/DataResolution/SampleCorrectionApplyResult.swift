/// A successful commit or the replacement review required before another Apply.
public enum SampleCorrectionApplyResult: Sendable {
    case applied
    case stale(GPSCorrectionReview?)
}
