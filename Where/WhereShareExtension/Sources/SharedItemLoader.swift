import Foundation
import PeriscopeCore
import UniformTypeIdentifiers
import WhereCore

/// Bytes pulled out of a share invocation, plus the hints needed to classify
/// and label them. A small named value (not a tuple) since it escapes the
/// loader into the compose model's state.
struct SharedAttachment {
    let data: Data
    /// Uniform type identifier the item provider offered the bytes as — the
    /// authoritative input to `EvidenceContentType.classify`.
    let typeIdentifier: String?
    /// Item provider's suggested display name, when it had one.
    let filename: String?
}

/// Extracts every usable attachment from the share sheet's extension items.
///
/// Share invocations carry one or more `NSExtensionItem`s, each with a list of
/// `NSItemProvider`s that can vend the same content in several representations
/// (a PDF also advertised as a file, a photo as several image formats, an email
/// as a file *and* a URL). We take one attachment per provider — its most
/// preview-friendly representation: PDF, then image, then any concrete file,
/// then text, then a URL (captured as its string) — so sharing several items at
/// once (the activation rule allows up to 20) captures all of them rather than
/// silently keeping just the first. Everything runs on the main actor so the
/// non-`Sendable` providers are never sent across actors.
@MainActor
enum SharedItemLoader {
    private static let logger = WhereLog.root(ShareExtensionLog.self)

    /// Load every attachment the providers in `items` can produce, one per
    /// provider, in share order. Empty when nothing yields bytes (the compose
    /// form then saves metadata only).
    static func loadAttachments(from items: [NSExtensionItem]) async -> [SharedAttachment] {
        var attachments: [SharedAttachment] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if let attachment = await load(from: provider) {
                    attachments.append(attachment)
                }
            }
        }
        return attachments
    }

    private static func load(from provider: NSItemProvider) async -> SharedAttachment? {
        let types = provider.registeredContentTypes
        if let pdf = types.first(where: { $0.conforms(to: .pdf) }) {
            return await loadData(from: provider, as: pdf)
        }
        if let image = types.first(where: { $0.conforms(to: .image) }) {
            return await loadData(from: provider, as: image)
        }
        // Any concrete file/binary that isn't really a URL or text — covers
        // Wallet passes (`.pkpass`), `.eml` emails, archives, and the like.
        if let file = types.first(where: {
            $0.conforms(to: .data) && !$0.conforms(to: .url) && !$0.conforms(to: .text)
        }) {
            return await loadData(from: provider, as: file)
        }
        if let text = types.first(where: { $0.conforms(to: .text) }) {
            return await loadData(from: provider, as: text)
        }
        if let url = types.first(where: { $0.conforms(to: .url) }) {
            return await loadURL(from: provider, as: url)
        }
        return nil
    }

    private static func loadData(
        from provider: NSItemProvider,
        as type: UTType,
    ) async -> SharedAttachment? {
        // `loadDataRepresentation` returns `Progress`, so Swift gives it no
        // auto-generated async form — bridge the completion handler and resume
        // with the `Sendable` bytes only, logging back on the actor.
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        guard let data else {
            logger { .attachmentLoadFailed(typeIdentifier: type.identifier) }
            return nil
        }
        return SharedAttachment(
            data: data,
            typeIdentifier: type.identifier,
            filename: provider.suggestedName,
        )
    }

    /// Load a shared URL and keep it as UTF-8 plain-text bytes so a link (e.g. a
    /// forwarded reservation page) is still captured as evidence. Extracts the
    /// string inside the completion so only a `Sendable` value crosses back to
    /// the actor.
    private static func loadURL(
        from provider: NSItemProvider,
        as type: UTType,
    ) async -> SharedAttachment? {
        let string: String? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                switch item {
                    case let url as URL: continuation.resume(returning: url.absoluteString)
                    case let text as String: continuation.resume(returning: text)
                    default: continuation.resume(returning: nil)
                }
            }
        }
        guard let string else {
            logger { .urlUnreadable }
            return nil
        }
        return SharedAttachment(
            data: Data(string.utf8),
            typeIdentifier: UTType.plainText.identifier,
            filename: provider.suggestedName,
        )
    }
}
