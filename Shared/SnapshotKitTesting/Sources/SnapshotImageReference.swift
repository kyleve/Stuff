import ImageIO
import SnapshotTesting
import UIKit
import UniformTypeIdentifiers

/// One PNG reference. Cutsheets carry their approved panel map in PNG Description;
/// ordinary captures retain the standard PNG encoding and comparison behavior.
@MainActor
struct SnapshotImageReference {
    let image: UIImage
    let layout: SnapshotComparisonLayout?

    private struct Metadata: Codable {
        let version: Int
        let layout: SnapshotComparisonLayout
    }

    enum Failure: Error {
        case invalidPNG
        case invalidMetadata
        case unsupportedVersion(Int)
        case encodingFailed
    }

    func pngData() throws -> Data {
        guard let png = image.pngData() else { throw Failure.invalidPNG }
        guard let layout else { return png }
        let metadata = try JSONEncoder().encode(Metadata(version: 1, layout: layout))
        guard let source = CGImageSourceCreateWithData(png as CFData, nil) else {
            throw Failure.invalidPNG
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil,
        ) else {
            throw Failure.encodingFailed
        }
        CGImageDestinationAddImageFromSource(destination, source, 0, [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyPNGDescription: String(decoding: metadata, as: UTF8.self),
            ],
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encodingFailed }
        return data as Data
    }

    init(image: UIImage, layout: SnapshotComparisonLayout?) {
        self.image = image
        self.layout = layout
    }

    init(png: Data) throws {
        guard let image = UIImage(data: png),
              let source = CGImageSourceCreateWithData(png as CFData, nil)
        else { throw Failure.invalidPNG }
        self.image = image
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dictionary = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        if let description = dictionary?[kCGImagePropertyPNGDescription] as? String {
            let metadata = try JSONDecoder().decode(Metadata.self, from: Data(description.utf8))
            guard metadata.version == 1 else { throw Failure.unsupportedVersion(metadata.version) }
            layout = metadata.layout
            try validateLayout()
        } else {
            layout = nil
        }
    }

    private func validateLayout() throws {
        guard let layout, let pixels = image.cgImage,
              layout.pixelSize == CGSize(width: pixels.width, height: pixels.height),
              !layout.panels.isEmpty,
              Set(layout.panels.map(\.identity)).count == layout.panels.count
        else { throw Failure.invalidMetadata }
        let canvas = CGRect(origin: .zero, size: layout.pixelSize)
        for panel in layout.panels {
            let bounds = panel.bounds
            guard bounds.width > 0, bounds.height > 0,
                  bounds == bounds.integral, canvas.contains(bounds)
            else { throw Failure.invalidMetadata }
        }
    }

    struct ComparisonFailure {
        let message: String
        let attachments: [DiffAttachment]
    }

    private static var imageDiff: Diffing<UIImage> {
        Snapshotting<UIImage, UIImage>.image(
            precision: defaultSnapshotPrecision,
            perceptualPrecision: defaultSnapshotPerceptualPrecision,
        ).diffing
    }

    /// Compares the independent captures before any sheet pixels are composed.
    static func comparePanels(
        referencePNG: Data,
        sheet: SnapshotComparisonSheet,
    ) -> ComparisonFailure? {
        do {
            let reference = try Self(png: referencePNG)
            guard let layout = reference.layout else {
                return ComparisonFailure(
                    message: "Cutsheet reference is missing its embedded panel map; record the reference again.",
                    attachments: [],
                )
            }
            var messages: [String] = []
            var attachments: [DiffAttachment] = []
            if layout != sheet.layout {
                messages.append("Cutsheet panel membership, labels, or geometry changed.")
            }
            let references = Dictionary(uniqueKeysWithValues: layout.panels
                .map { ($0.identity, $0) })
            for panel in sheet.panels {
                guard let placement = references[panel.identity] else {
                    messages
                        .append(
                            "Missing reference panel: \(panel.label) (\(panel.identity.rawValue)).",
                        )
                    continue
                }
                guard let pixels = reference.image.cgImage?.cropping(to: placement.bounds) else {
                    throw Failure.invalidMetadata
                }
                if let failure = imageDiff.diffV2(
                    UIImage(cgImage: pixels, scale: panel.image.scale, orientation: .up),
                    panel.image,
                ) {
                    messages
                        .append("Panel \(panel.label) (\(panel.identity.rawValue)): \(failure.0)")
                    attachments += failure.1
                }
            }
            return messages.isEmpty ? nil : ComparisonFailure(
                message: messages.joined(separator: "\n\n"),
                attachments: attachments,
            )
        } catch {
            return ComparisonFailure(
                message: "Cannot compare snapshot PNG: \(error)",
                attachments: [],
            )
        }
    }

    /// Delegates recording policy to SnapshotTesting after panel verification.
    /// The whole-image comparator also guards headings and spacing.
    static func strategy(panelFailure: ComparisonFailure?) -> Snapshotting<Data, Data> {
        Snapshotting(pathExtension: "png", diffing: .diff(
            toData: { $0 },
            fromData: { $0 },
            diffV2: { oldData, newData in
                do {
                    let old = try Self(png: oldData)
                    let new = try Self(png: newData)
                    let imageFailure = imageDiff.diffV2(old.image, new.image)
                    let messages = [panelFailure?.message, imageFailure?.0].compactMap(\.self)
                    let attachments = (panelFailure?.attachments ?? []) + (imageFailure?.1 ?? [])
                    return messages.isEmpty ? nil : (
                        messages.joined(separator: "\n\n"),
                        attachments
                    )
                } catch {
                    return ("Cannot compare snapshot PNG: \(error)", [])
                }
            },
        ))
    }
}
