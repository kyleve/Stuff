import CoreGraphics
import Foundation
import ImageIO

/// Compare independently exported pixels in one premultiplied sRGB representation.
private struct Bitmap {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw CocoaError(.fileReadCorruptFile) }
        let w = image.width
        let h = image.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo
                    .byteOrder32Big.rawValue,
            ) else { throw CocoaError(.fileReadCorruptFile) }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        (width, height, bytes) = (w, h, pixels)
    }
}

private func compare(_ left: URL, _ right: URL, label: String) throws -> Bool {
    if try Data(contentsOf: left) == Data(contentsOf: right) {
        print("\(label) — identical PNG")
        return true
    }
    let a = try Bitmap(left)
    let b = try Bitmap(right)
    guard a.width == b.width, a.height == b.height else {
        print("\(label) — size \(a.width)×\(a.height) versus \(b.width)×\(b.height)")
        return false
    }
    var changed = 0
    var changedAlpha = 0
    var maximum = 0
    for i in stride(from: 0, to: a.bytes.count, by: 4) {
        var delta = 0
        for channel in i ..< i + 4 {
            delta = max(delta, abs(Int(a.bytes[channel]) - Int(b.bytes[channel])))
        }
        if a.bytes[i + 3] != b.bytes[i + 3] { changedAlpha += 1 }
        if delta > 0 { changed += 1 }
        maximum = max(maximum, delta)
    }
    print(
        "\(label) — \(changed)/\(a.width * a.height) changed pixels, \(changedAlpha) alpha differences, max channel delta \(maximum)",
    )
    return changed == 0
}

private struct Portrait: Decodable {
    let id: String
    let backend: String
    let reference: String
}

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError
        .write(Data("Usage: swift audit-frames.swift <experiment-output>\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: args[1], isDirectory: true)
var nativeMatches = 0
var failedLocations: [String] = []
for pass in ["first", "repeat"] {
    let dir = output.appendingPathComponent(pass)
    let portraits = try JSONDecoder().decode(
        [Portrait].self,
        from: Data(contentsOf: dir.appendingPathComponent("banner/results.json")),
    )
    guard portraits.count == 40, Set(portraits.map { $0.backend + "/" + $0.id }).count == 40 else {
        throw CocoaError(.fileReadCorruptFile)
    }
    for row in portraits {
        let relative = "banner/\(row.backend)/\(row.id).png"
        let same = try compare(
            dir.appendingPathComponent(relative),
            URL(fileURLWithPath: row.reference),
            label: "\(pass)/\(relative)",
        )
        if row.backend == "native", same { nativeMatches += 1 }
    }
    for stage in ["loading", "loaded", "selected"] {
        let candidate = "locations/candidate/\(stage).png"
        let oracle = "locations/oracle/\(stage).png"
        let withinPass = "\(pass)/Locations/\(stage) against delayed host"
        if try !compare(
            dir.appendingPathComponent(candidate),
            dir.appendingPathComponent(oracle),
            label: withinPass,
        ) {
            failedLocations.append(withinPass)
        }
        if pass == "repeat" {
            for relative in [candidate, oracle] {
                let acrossRuns = "\(relative) across runs"
                if try !compare(
                    dir.appendingPathComponent(relative),
                    output.appendingPathComponent("first/" + relative),
                    label: acrossRuns,
                ) {
                    failedLocations.append(acrossRuns)
                }
            }
        }
    }
}

if nativeMatches != 40 || !failedLocations.isEmpty {
    let report = "Matched \(nativeMatches)/40 native Banner frames. Locations differences: \(failedLocations.joined(separator: ", ")).\n"
    FileHandle.standardError.write(Data(report.utf8))
    exit(1)
}
