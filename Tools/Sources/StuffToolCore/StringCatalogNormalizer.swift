import Foundation

/// Discovers and normalizes String Catalogs without owning command-line I/O.
public struct StringCatalogNormalizer: Sendable {
    public init() {}

    public func normalized(_ url: URL) throws -> Data {
        let original = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: original)
        let rewritten = try CatalogSerializer().data(from: object)
        let reparsed = try JSONSerialization.jsonObject(with: rewritten)
        guard NSDictionary(dictionary: object as? [String: Any] ?? [:])
            .isEqual(to: reparsed as? [String: Any] ?? [:])
        else {
            throw CatalogSerializer.Failure.unsupportedValue(
                "\(type(of: object)) (\(object))",
            )
        }
        return rewritten
    }

    public func catalogs(under root: URL) throws -> [URL] {
        let skipped: Set = ["Derived", ".build", ".git", "build"]
        var found: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }
        while let url = enumerator.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true,
               skipped.contains(url.lastPathComponent) || url.pathExtension == "xcodeproj"
            {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcstrings" {
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    @discardableResult
    public func normalize(
        _ targets: [URL],
        lintOnly: Bool,
        displayRoot: URL,
        report: (String) -> Void,
    ) throws -> [URL] {
        var offenders: [URL] = []
        let rootPath = displayRoot.standardizedFileURL.path
        let root = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        for url in targets {
            let rewritten = try normalized(url)
            guard try rewritten != Data(contentsOf: url) else { continue }
            offenders.append(url)
            let path = url.standardizedFileURL.path
            let display = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
            if lintOnly {
                report("not normalized: \(display)")
            } else {
                try rewritten.write(to: url, options: .atomic)
                report("normalized: \(display)")
            }
        }
        return offenders
    }
}
