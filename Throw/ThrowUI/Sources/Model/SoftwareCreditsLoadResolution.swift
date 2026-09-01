import CreditKit
import ThrowCore

/// The composition result that keeps attribution UI state and its diagnostic consistent.
enum SoftwareCreditsLoadResolution {
    case loaded([SoftwareCredit])
    case failed(ThrowSoftwareCreditsLoadFailure)

    var state: SoftwareCreditsLoadState {
        switch self {
            case let .loaded(credits):
                .loaded(credits)
            case .failed:
                .failed
        }
    }

    var failure: ThrowSoftwareCreditsLoadFailure? {
        switch self {
            case .loaded:
                nil
            case let .failed(failure):
                failure
        }
    }
}
