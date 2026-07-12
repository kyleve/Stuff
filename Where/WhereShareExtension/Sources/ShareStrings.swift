import Foundation

/// Compose-sheet chrome resolved from this extension's own string catalog.
/// Evidence *kind* names and symbols come from WhereUI's `EvidenceKind`
/// presentation helpers so they read identically to the in-app form; only the
/// extension-specific copy lives here (mirroring `WidgetStrings`).
enum ShareStrings {
    static var title: String {
        String(localized: "share.title", defaultValue: "Save to Where", bundle: .module)
    }

    static var loading: String {
        String(localized: "share.loading", defaultValue: "Preparing…", bundle: .module)
    }

    static var save: String {
        String(localized: "share.save", defaultValue: "Save", bundle: .module)
    }

    static var cancel: String {
        String(localized: "share.cancel", defaultValue: "Cancel", bundle: .module)
    }

    static var ok: String {
        String(localized: "share.ok", defaultValue: "OK", bundle: .module)
    }

    static var attachmentHeader: String {
        String(localized: "share.attachment.header", defaultValue: "Attachment", bundle: .module)
    }

    static var noAttachment: String {
        String(
            localized: "share.attachment.none",
            defaultValue: "No attachment — this will save a note only.",
            bundle: .module,
        )
    }

    static var kindLabel: String {
        String(localized: "share.form.kind", defaultValue: "Kind", bundle: .module)
    }

    static var otherLabelPlaceholder: String {
        String(localized: "share.form.otherLabel", defaultValue: "Label", bundle: .module)
    }

    static var dateLabel: String {
        String(localized: "share.form.date", defaultValue: "Date", bundle: .module)
    }

    static var noteHeader: String {
        String(localized: "share.form.noteHeader", defaultValue: "Note", bundle: .module)
    }

    static var notePlaceholder: String {
        String(
            localized: "share.form.notePlaceholder",
            defaultValue: "Add a note (optional)",
            bundle: .module,
        )
    }

    static var saveErrorTitle: String {
        String(
            localized: "share.saveError.title",
            defaultValue: "Couldn't save",
            bundle: .module,
        )
    }
}
