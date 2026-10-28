import Foundation
import InstallerKit

/// Localizes failure reasons at the UI boundary without replacing the model's original error.
struct UpdateFailureDescription {
    let message: String
    let code: String

    init(error: any Error) {
        switch error {
            case let error as UpdateClient.FetchError:
                switch error {
                    case .invalidResponse:
                        message = String(localized: .installerFailureInvalidResponse)
                        code = "InstallerKit.invalidResponse"
                    case .unexpectedLocation:
                        message = String(localized: .installerFailureUnexpectedLocation)
                        code = "InstallerKit.unexpectedLocation"
                    case let .httpStatus(status):
                        message = Self.httpMessage(status: status)
                        code = "HTTP \(status)"
                    case .responseTooLarge:
                        message = String(localized: .installerFailureResponseTooLarge)
                        code = "InstallerKit.responseTooLarge"
                }
            case let error as DecodingError:
                message = String(localized: .installerFailureInvalidData)
                switch error {
                    case .dataCorrupted: code = "DecodingError.dataCorrupted"
                    case .keyNotFound: code = "DecodingError.keyNotFound"
                    case .typeMismatch: code = "DecodingError.typeMismatch"
                    case .valueNotFound: code = "DecodingError.valueNotFound"
                    @unknown default: code = "DecodingError"
                }
            case let error as UpdateCatalog.ValidationError:
                switch error {
                    case .invalidCatalog:
                        message = String(localized: .installerFailureInvalidCatalog)
                        code = "InstallerKit.invalidCatalog"
                }
            case let error as URLError:
                message = Self.networkMessages[error.code].map { String(localized: $0) }
                    ?? error.localizedDescription
                code = "\(NSURLErrorDomain) \(error.code.rawValue)"
            default:
                // Preserve unfamiliar errors' descriptions and domains instead of guessing a cause.
                let error = error as NSError
                message = error.localizedDescription
                code = "\(error.domain) \(error.code)"
        }
    }

    /// URL errors constructed without userInfo can have a generic localizedDescription.
    /// Known codes must still explain the actual failure.
    private static let networkMessages: [URLError.Code: LocalizedStringResource] = [
        .notConnectedToInternet: .installerFailureOffline,
        .timedOut: .installerFailureTimeout,
        .cannotFindHost: .installerFailureHostNotFound,
        .dnsLookupFailed: .installerFailureHostNotFound,
        .cannotConnectToHost: .installerFailureCannotConnect,
        .networkConnectionLost: .installerFailureConnectionLost,
        .dataNotAllowed: .installerFailureDataNotAllowed,
        .secureConnectionFailed: .installerFailureSecureConnection,
        .appTransportSecurityRequiresSecureConnection: .installerFailureSecureConnection,
        .serverCertificateHasBadDate: .installerFailureCertificate,
        .serverCertificateUntrusted: .installerFailureCertificate,
        .serverCertificateHasUnknownRoot: .installerFailureCertificate,
        .serverCertificateNotYetValid: .installerFailureCertificate,
        .clientCertificateRejected: .installerFailureClientCertificate,
        .clientCertificateRequired: .installerFailureClientCertificate,
    ]

    private static func httpMessage(status: Int) -> String {
        switch status {
            case 401: String(localized: .installerFailureAuthentication)
            case 403: String(localized: .installerFailureAccessDenied)
            case 404: String(localized: .installerFailureFeedNotFound)
            case 410: String(localized: .installerFailureFeedGone)
            case 429: String(localized: .installerFailureRateLimited)
            case 500 ... 599: String(localized: .installerFailureServer)
            default: String(localized: .installerFailureHttpStatus)
        }
    }
}
