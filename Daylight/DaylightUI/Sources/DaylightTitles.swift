import DaylightCore
import DaylightMastodon
import Foundation

extension CaptureSettings.Camera.Lens {
    var title: LocalizedStringResource {
        switch self {
            case .main: .lensMain; case .ultraWide: .lensUltraWide; case .telephoto: .lensTelephoto
        }
    }
}

extension SolarEvent.Kind {
    var title: LocalizedStringResource {
        switch self { case .sunrise: .eventSunrise; case .sunset: .eventSunset }
    }
}

extension MastodonSettings.Visibility {
    var title: LocalizedStringResource {
        switch self {
            case .public: .visibilityPublic; case .unlisted: .visibilityUnlisted; case .private: .visibilityPrivate
        }
    }
}

extension CaptureSequence.Slot.State {
    var title: String {
        switch self {
            case .pending: String(localized: .slotPending)
            case .missed: String(localized: .slotMissed)
            case .capturing: String(localized: .slotCapturing)
            case let .failed(message): message
            case let .captured(image):
                switch image.photos {
                    case .saved:
                        switch image.format {
                            case .rawAndJPEG: String(localized: .photosSavedRaw)
                            case .jpeg: String(localized: .photosSavedJpeg)
                            case nil: String(localized: .photosSaved)
                        }
                    case .pending, .saving: String(localized: .photosSaving)
                    case let .failed(message), let .retry(_, message): message
                    case .ambiguous: String(localized: .photosAmbiguous)
                }
        }
    }
}

extension CapturedImage.PhotosState {
    var title: String {
        switch self {
            case .saved: String(localized: .photosSaved)
            case .pending, .saving: String(localized: .photosSaving)
            case let .failed(message), let .retry(_, message): message
            case .ambiguous: String(localized: .photosAmbiguous)
        }
    }
}
