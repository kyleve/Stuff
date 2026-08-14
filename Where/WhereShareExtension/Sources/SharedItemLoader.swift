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

/// What a provider returned for one representation, reduced to `Sendable`
/// pieces so nothing non-`Sendable` crosses back out of the completion handler.
///
/// One value rather than a payload beside an `(any Error)?`: the callback can
/// hand back either, neither, or both, while only "here it is" and "nothing, and
/// here's why (if it said)" mean anything — so the rest can't be spelled. A
/// nil-value/nil-error callback is a real case, and the one the discarded-error
/// code couldn't tell apart from a reported failure.
private enum LoadedValue<Value: Sendable> {
    case loaded(Value)
    case missing(reason: String?)

    init(value: Value?, error: (any Error)?) {
        if let value {
            self = .loaded(value)
        } else {
            self = .missing(reason: error.map { String(describing: $0) })
        }
    }
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
        await logger.measure(.loadAttachments, budget: .seconds(3)) {
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
        // with `Sendable` pieces only, logging back on the actor.
        let loaded: LoadedValue<Data> = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                continuation.resume(returning: LoadedValue(value: data, error: error))
            }
        }
        switch loaded {
            case let .loaded(data):
                return SharedAttachment(
                    data: data,
                    typeIdentifier: type.identifier,
                    filename: provider.suggestedName,
                )
            case let .missing(reason):
                logger.attachmentLoadFailed(
                    typeIdentifier: .restricted(.identifier, type.identifier),
                    reason: .restricted(.errorDetails, reason),
                )
                return nil
        }
    }

    /// Load a shared URL and keep it as UTF-8 plain-text bytes so a link (e.g. a
    /// forwarded reservation page) is still captured as evidence. Extracts the
    /// string inside the completion so only a `Sendable` value crosses back to
    /// the actor.
    private static func loadURL(
        from provider: NSItemProvider,
        as type: UTType,
    ) async -> SharedAttachment? {
        let loaded: LoadedValue<String> = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                let string: String? = switch item {
                    case let url as URL: url.absoluteString
                    case let text as String: text
                    default: nil
                }
                continuation.resume(returning: LoadedValue(value: string, error: error))
            }
        }
        switch loaded {
            case let .loaded(string):
                return SharedAttachment(
                    data: Data(string.utf8),
                    typeIdentifier: UTType.plainText.identifier,
                    filename: provider.suggestedName,
                )
            case let .missing(reason):
                logger.urlUnreadable(reason: .restricted(.errorDetails, reason))
                return nil
        }
    }
}
