import PeriscopeCore

/// Structured events and spans for the Where share extension.
@LogScope("ShareExtension")
enum ShareExtensionLog {
    enum SpanName: Hashable {
        case loadAttachments
    }

    @LogEvent("opened", level: .info)
    struct Opened {
        @LogField(exposure: .restricted, kind: .count)
        var itemCount: Int

        var message: String {
            "Share extension opened with \(itemCount) item(s)"
        }
    }

    @LogEvent("attachment-load-failed", level: .warning)
    struct AttachmentLoadFailed {
        @LogField(exposure: .restricted, kind: .identifier)
        var typeIdentifier: String

        @LogField(exposure: .restricted, kind: .errorDetails)
        var reason: String?

        var message: String {
            "Failed to load shared \(typeIdentifier): \(reason ?? "provider returned nothing")"
        }
    }

    @LogEvent("url-unreadable", level: .warning)
    struct URLUnreadable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var reason: String?

        var message: String {
            "Shared URL provider yielded no readable URL: \(reason ?? "provider returned nothing")"
        }
    }

    @LogEvent("saved", level: .info)
    struct Saved {
        @LogField(exposure: .restricted, kind: .count)
        var evidenceCount: Int

        var message: String {
            "Saved \(evidenceCount) shared evidence record(s)"
        }
    }

    @LogEvent("save-failed", level: .error)
    struct SaveFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var description: String

        var message: String {
            "Failed to save shared evidence: \(description)"
        }
    }
}
