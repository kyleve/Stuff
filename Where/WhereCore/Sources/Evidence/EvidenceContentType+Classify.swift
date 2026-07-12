import Foundation
import UniformTypeIdentifiers

extension EvidenceContentType {
    /// Best-effort classification of attachment bytes into a rendering hint for
    /// the evidence viewer.
    ///
    /// A caller-supplied uniform type identifier (from an `NSItemProvider`, a
    /// file import, or a photo pick) is authoritative when it resolves to a
    /// known `UTType` family; otherwise the leading "magic" bytes are sniffed.
    /// Anything unrecognized becomes `.other(typeIdentifier)` — so the blob is
    /// still attributable by its declared type — or `.rawData` when there's
    /// nothing at all to go on. Never throws: an unknown format is a normal,
    /// representable outcome, not an error.
    public static func classify(
        data: Data,
        typeIdentifier: String?,
    ) -> EvidenceContentType {
        if let identifier = typeIdentifier, let type = UTType(identifier) {
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .plainText) { return .plainText }
        }
        if let sniffed = sniff(data) { return sniffed }
        // Fall back to the declared type as a label so a still-unknown blob is
        // at least attributable, else raw bytes with no hint at all.
        if let identifier = typeIdentifier { return .other(identifier) }
        return .rawData
    }

    /// Classify by the leading bytes alone, for the common PDF/image formats.
    /// Returns `nil` when nothing matches so the caller can fall back. Works off
    /// a copied prefix array so `Data`'s (possibly non-zero) slice indices can't
    /// trip up the offset checks.
    private static func sniff(_ data: Data) -> EvidenceContentType? {
        let bytes = Array(data.prefix(16))
        func matches(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            return Array(bytes[offset ..< offset + signature.count]) == signature
        }
        if matches([0x25, 0x50, 0x44, 0x46]) { return .pdf } // "%PDF"
        if matches([0xFF, 0xD8, 0xFF]) { return .image } // JPEG
        if matches([0x89, 0x50, 0x4E, 0x47]) { return .image } // PNG
        if matches([0x47, 0x49, 0x46, 0x38]) { return .image } // "GIF8"
        // HEIC/HEIF and other ISO base-media files: "ftyp" box at offset 4.
        if matches([0x66, 0x74, 0x79, 0x70], at: 4) { return .image }
        // WEBP: "RIFF"????"WEBP".
        if matches([0x52, 0x49, 0x46, 0x46]), matches([0x57, 0x45, 0x42, 0x50], at: 8) {
            return .image
        }
        return nil
    }
}
