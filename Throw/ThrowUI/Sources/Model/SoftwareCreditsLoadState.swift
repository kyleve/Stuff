import CreditKit

/// The result of loading the software attribution report bundled with Throw.
public enum SoftwareCreditsLoadState: Equatable, Sendable {
    /// The report loaded successfully, including a valid report with no credits.
    case loaded([SoftwareCredit])
    /// The bundled report could not be loaded.
    case failed
}
