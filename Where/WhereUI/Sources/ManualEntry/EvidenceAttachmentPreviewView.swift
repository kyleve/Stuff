import SwiftUI
import WhereCore

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

struct EvidenceAttachmentPreviewView: View {
    let attachment: EvidenceAttachment
    let stagedURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.originalFilename)
                    .lineLimit(1)
                Text(metadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let previewImage {
            previewImage
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: 56, height: 56)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: iconName)
                            .font(.title3)
                        Text(fileTypeLabel)
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
        }
    }

    private var previewImage: Image? {
        guard attachment.contentType.hasPrefix("image/"), let stagedURL else {
            return nil
        }

        #if canImport(UIKit)
            guard let image = UIImage(contentsOfFile: stagedURL.path) else {
                return nil
            }
            return Image(uiImage: image)
        #elseif canImport(AppKit)
            guard let image = NSImage(contentsOf: stagedURL) else {
                return nil
            }
            return Image(nsImage: image)
        #else
            return nil
        #endif
    }

    private var metadataText: String {
        "\(attachment.contentType) • \(attachment.byteCount) bytes"
    }

    private var fileTypeLabel: String {
        if attachment.contentType == "application/pdf" {
            return "PDF"
        }

        if attachment.contentType.hasPrefix("text/") {
            return "TXT"
        }

        if attachment.contentType.hasPrefix("image/") {
            return "IMG"
        }

        let fileExtension = URL(fileURLWithPath: attachment.originalFilename).pathExtension
        if !fileExtension.isEmpty {
            return fileExtension.uppercased()
        }

        return "FILE"
    }

    private var iconName: String {
        if attachment.contentType == "application/pdf" {
            return "doc.richtext"
        }

        if attachment.contentType.hasPrefix("text/") {
            return "doc.plaintext"
        }

        if attachment.contentType.hasPrefix("image/") {
            return "photo"
        }

        return "doc"
    }
}
