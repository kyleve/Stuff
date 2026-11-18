import Foundation
import ImageIO

/// A successful comparison is reusable only for these exact two byte sequences.
struct SnapshotPreparedMatch {
    let reference: Data
    let capture: Data
    let diagnostic: SnapshotReferenceComparison?

    func matches(reference: Data, capture: Data) -> Bool {
        self.reference == reference && self.capture == capture
    }
}

struct SnapshotPreparedComparison {
    /// Keep comparison buffers bounded while another capture is hosted.
    /// Larger images retain the serial path measured by the overlap experiment.
    static let maximumPixelCount = 12_000_000

    enum Outcome {
        case matched(SnapshotPreparedMatch)
        case serial
        case cancelled
    }

    let outcome: Outcome
    let duration: TimeInterval
}

/// Only immutable PNG bytes enter this worker. Hosting and reporting remain serial.
@concurrent
func prepareSnapshotReference(
    capturedPNG: Data,
    referenceURL: URL,
    diagnostics: Bool,
) async -> SnapshotPreparedComparison {
    let start = ProcessInfo.processInfo.systemUptime
    let outcome: SnapshotPreparedComparison.Outcome = autoreleasepool {
        guard !Task.isCancelled else { return .cancelled }
        guard let referencePNG = try? Data(contentsOf: referenceURL),
              let referenceSize = pngPixelSize(referencePNG),
              let capturedSize = pngPixelSize(capturedPNG),
              referenceSize == capturedSize,
              capturedSize.width * capturedSize.height
              <= CGFloat(SnapshotPreparedComparison.maximumPixelCount)
        else { return .serial }
        guard !Task.isCancelled else { return .cancelled }
        guard SnapshotImageReference.strategy(panelFailure: nil).diffing
            .diffV2(referencePNG, capturedPNG) == nil
        else { return .serial }
        guard !Task.isCancelled else { return .cancelled }
        let diagnostic = diagnostics
            ? compareSnapshotPNGs(
                capturedPNG: capturedPNG,
                referencePNG: referencePNG,
                referenceURL: referenceURL,
            )
            : nil
        guard !Task.isCancelled else { return .cancelled }
        return .matched(SnapshotPreparedMatch(
            reference: referencePNG,
            capture: capturedPNG,
            diagnostic: diagnostic,
        ))
    }
    return SnapshotPreparedComparison(
        outcome: outcome,
        duration: ProcessInfo.processInfo.systemUptime - start,
    )
}

/// Read dimensions before decoding, including an unexpectedly large old reference.
private func pngPixelSize(_ png: Data) -> CGSize? {
    guard let source = CGImageSourceCreateWithData(png as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
    else { return nil }
    return CGSize(width: width.doubleValue, height: height.doubleValue)
}
