import Foundation

public struct AppIconDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let alternateIconName: String?
    public let previewImageName: String

    public init(
        id: String,
        displayName: String,
        alternateIconName: String?,
        previewImageName: String,
    ) {
        self.id = id
        self.displayName = displayName
        self.alternateIconName = alternateIconName
        self.previewImageName = previewImageName
    }
}

public struct AppIconManifest: Codable, Equatable, Sendable {
    public var icons: [AppIconDescriptor]

    public init(icons: [AppIconDescriptor]) {
        self.icons = icons
    }
}

public struct IconImageData: Equatable, Sendable {
    public let data: Data

    public init(data: Data, pathDescription: String) throws {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data.prefix(8)) == signature else {
            throw IconCatalogFailure.message("not a PNG: \(pathDescription)")
        }
        let width = Self.bigEndianUInt32(data[16 ..< 20])
        let height = Self.bigEndianUInt32(data[20 ..< 24])
        guard width == 1024, height == 1024 else {
            throw IconCatalogFailure.message(
                "\(pathDescription) is \(width)x\(height); app icons must be 1024x1024",
            )
        }
        self.data = data
    }

    private static func bigEndianUInt32(_ bytes: Data.SubSequence) -> UInt32 {
        bytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}

public struct IconAdditionPlan: Equatable, Sendable {
    public let setName: String
    public let icon: AppIconDescriptor
    public let manifest: AppIconManifest
    public let light: IconImageData
    public let dark: IconImageData?
    public let tinted: IconImageData?

    public init(
        setName: String,
        icon: AppIconDescriptor,
        manifest: AppIconManifest,
        light: IconImageData,
        dark: IconImageData?,
        tinted: IconImageData?,
    ) {
        self.setName = setName
        self.icon = icon
        self.manifest = manifest
        self.light = light
        self.dark = dark
        self.tinted = tinted
    }
}

public struct IconRemovalPlan: Equatable, Sendable {
    public let icon: AppIconDescriptor
    public let manifest: AppIconManifest

    public init(icon: AppIconDescriptor, manifest: AppIconManifest) {
        self.icon = icon
        self.manifest = manifest
    }
}

public enum IconCatalogFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)

    public var description: String {
        switch self {
            case let .message(message): message
        }
    }
}

/// Parses and calculates complete icon-catalog operations without touching disk.
public struct IconCatalogPlanner: Sendable {
    private static let primarySet = "AppIcon"
    private static let primaryID = "classic"

    public init() {}

    public func decodeManifest(_ data: Data, pathDescription: String) throws -> AppIconManifest {
        let manifest: AppIconManifest
        do {
            manifest = try JSONDecoder().decode(AppIconManifest.self, from: data)
        } catch {
            throw IconCatalogFailure.message(
                "\(pathDescription) is not valid JSON: \(error)",
            )
        }
        try validate(manifest)
        return manifest
    }

    public func addition(
        manifest: AppIconManifest,
        light: IconImageData,
        lightFilename: String,
        name explicitName: String?,
        id explicitID: String?,
        dark: IconImageData?,
        tinted: IconImageData?,
    ) throws -> IconAdditionPlan {
        let sourceStem = URL(filePath: lightFilename).deletingPathExtension().lastPathComponent
        let name = explicitName ?? Self.pascalCase(sourceStem)
        guard name.isEmpty == false else {
            throw IconCatalogFailure.message("couldn't derive a name; pass --name")
        }
        let id = explicitID ?? Self.slug(name)
        guard id.isEmpty == false else {
            throw IconCatalogFailure.message("couldn't derive an id; pass --id")
        }
        let setName = Self.primarySet + Self.pascalCase(name)
        guard setName != Self.primarySet, id != Self.primaryID else {
            throw IconCatalogFailure.message(
                "\"\(Self.primaryID)\" / \"\(Self.primarySet)\" is the reserved primary icon",
            )
        }
        guard manifest.icons.contains(where: { $0.id == id }) == false else {
            throw IconCatalogFailure.message(
                "an icon with id \"\(id)\" already exists (use --id to pick another)",
            )
        }
        guard manifest.icons.contains(where: { $0.alternateIconName == setName }) == false else {
            throw IconCatalogFailure.message("an icon named \"\(setName)\" already exists")
        }

        let icon = AppIconDescriptor(
            id: id,
            displayName: name,
            alternateIconName: setName,
            previewImageName: setName,
        )
        var updated = manifest
        updated.icons.append(icon)
        try validate(updated)
        return IconAdditionPlan(
            setName: setName,
            icon: icon,
            manifest: updated,
            light: light,
            dark: dark,
            tinted: tinted,
        )
    }

    public func removal(manifest: AppIconManifest, target: String) throws -> IconRemovalPlan {
        if [Self.primaryID, Self.primarySet.lowercased()].contains(target.lowercased()) {
            throw IconCatalogFailure.message("the primary \"Classic\" icon can't be removed")
        }
        guard let index = manifest.icons.firstIndex(where: { icon in
            [icon.id, icon.displayName, icon.alternateIconName ?? ""]
                .contains(where: { $0.lowercased() == target.lowercased() })
        }) else {
            throw IconCatalogFailure.message(
                "no icon matching \"\(target)\" (try ./icons --list)",
            )
        }
        let icon = manifest.icons[index]
        guard icon.alternateIconName != nil else {
            throw IconCatalogFailure.message("the primary \"Classic\" icon can't be removed")
        }
        var updated = manifest
        updated.icons.remove(at: index)
        try validate(updated)
        return IconRemovalPlan(icon: icon, manifest: updated)
    }

    private func validate(_ manifest: AppIconManifest) throws {
        var identifiers: Set<String> = []
        var alternateNames: Set<String> = []
        for icon in manifest.icons {
            guard icon.id.isEmpty == false else {
                throw IconCatalogFailure.message("the icon manifest contains an empty id")
            }
            guard icon.displayName.isEmpty == false else {
                throw IconCatalogFailure.message(
                    "the icon manifest contains an empty display name for \"\(icon.id)\"",
                )
            }
            guard icon.previewImageName.isEmpty == false else {
                throw IconCatalogFailure.message(
                    "the icon manifest contains an empty preview name for \"\(icon.id)\"",
                )
            }
            guard identifiers.insert(icon.id).inserted else {
                throw IconCatalogFailure.message(
                    "the icon manifest contains duplicate id \"\(icon.id)\"",
                )
            }
            if let alternate = icon.alternateIconName {
                guard alternateNames.insert(alternate).inserted else {
                    throw IconCatalogFailure.message(
                        "the icon manifest contains duplicate asset \"\(alternate)\"",
                    )
                }
                guard URL(filePath: alternate).lastPathComponent == alternate else {
                    throw IconCatalogFailure.message(
                        "the icon manifest contains invalid asset name \"\(alternate)\"",
                    )
                }
            }
        }
        guard manifest.icons.contains(where: {
            $0.id == Self.primaryID && $0.alternateIconName == nil
        }) else {
            throw IconCatalogFailure
                .message("the icon manifest is missing the Classic primary icon")
        }
    }

    private static func pascalCase(_ text: String) -> String {
        text
            .split(whereSeparator: {
                $0.isASCII == false || $0.isLetter == false && $0.isNumber == false
            })
            .map { part in
                guard let first = part.first else { return "" }
                return String(first).uppercased() + part.dropFirst()
            }
            .joined()
    }

    private static func slug(_ text: String) -> String {
        text.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}

/// Emits the exact two-space JSON layout historically produced by `./icons`.
public struct IconCatalogRenderer: Sendable {
    public init() {}

    public func manifestData(_ manifest: AppIconManifest) throws -> Data {
        try OrderedJSON.object([
            ("icons", .array(manifest.icons.map { icon in
                .object([
                    ("id", .string(icon.id)),
                    ("displayName", .string(icon.displayName)),
                    ("alternateIconName", icon.alternateIconName.map(OrderedJSON.string) ?? .null),
                    ("previewImageName", .string(icon.previewImageName)),
                ])
            })),
        ]).data()
    }

    public func appContentsData(
        setName: String,
        hasDark: Bool,
        hasTinted: Bool,
    ) throws -> Data {
        var images: [OrderedJSON] = [
            .object([
                ("filename", .string("\(setName).png")),
                ("idiom", .string("universal")),
                ("platform", .string("ios")),
                ("size", .string("1024x1024")),
            ]),
        ]
        if hasDark {
            images.append(
                appearanceImage(
                    value: "dark",
                    filename: "\(setName)-Dark.png",
                    appIcon: true,
                ),
            )
        }
        if hasTinted {
            images.append(
                appearanceImage(
                    value: "tinted",
                    filename: "\(setName)-Tinted.png",
                    appIcon: true,
                ),
            )
        }
        return try contentsData(images: images)
    }

    public func previewContentsData(setName: String, hasDark: Bool) throws -> Data {
        var images: [OrderedJSON] = [
            .object([
                ("filename", .string("\(setName).png")),
                ("idiom", .string("universal")),
            ]),
        ]
        if hasDark {
            images.append(
                appearanceImage(
                    value: "dark",
                    filename: "\(setName)-Dark.png",
                    appIcon: false,
                ),
            )
        }
        return try contentsData(images: images)
    }

    private func contentsData(images: [OrderedJSON]) throws -> Data {
        try OrderedJSON.object([
            ("images", .array(images)),
            ("info", .object([
                ("author", .string("xcode")),
                ("version", .integer(1)),
            ])),
        ]).data()
    }

    private func appearanceImage(value: String, filename: String, appIcon: Bool) -> OrderedJSON {
        var members: [(String, OrderedJSON)] = [
            ("appearances", .array([
                .object([
                    ("appearance", .string("luminosity")),
                    ("value", .string(value)),
                ]),
            ])),
            ("filename", .string(filename)),
            ("idiom", .string("universal")),
        ]
        if appIcon {
            members += [
                ("platform", .string("ios")),
                ("size", .string("1024x1024")),
            ]
        }
        return .object(members)
    }
}

private indirect enum OrderedJSON {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case integer(Int)
    case null

    func data() throws -> Data {
        var output = ""
        try render(indent: 0, into: &output)
        output += "\n"
        return Data(output.utf8)
    }

    private func render(indent: Int, into output: inout String) throws {
        switch self {
            case let .object(members):
                guard members.isEmpty == false else {
                    output += "{}"
                    return
                }
                output += "{\n"
                for (index, member) in members.enumerated() {
                    output += Self.padding(indent + 1)
                    output += try Self.fragment(member.0)
                    output += " : "
                    try member.1.render(indent: indent + 1, into: &output)
                    output += index == members.count - 1 ? "\n" : ",\n"
                }
                output += Self.padding(indent) + "}"
            case let .array(values):
                guard values.isEmpty == false else {
                    output += "[]"
                    return
                }
                output += "[\n"
                for (index, value) in values.enumerated() {
                    output += Self.padding(indent + 1)
                    try value.render(indent: indent + 1, into: &output)
                    output += index == values.count - 1 ? "\n" : ",\n"
                }
                output += Self.padding(indent) + "]"
            case let .string(value):
                output += try Self.fragment(value)
            case let .integer(value):
                output += String(value)
            case .null:
                output += "null"
        }
    }

    private static func fragment(_ string: String) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: [string],
            options: [.withoutEscapingSlashes],
        )
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }

    private static func padding(_ indent: Int) -> String {
        String(repeating: "  ", count: indent)
    }
}
