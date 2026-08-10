import Foundation

public struct DeviceSelection: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let connectionState: String

    public init(identifier: String, name: String, connectionState: String) {
        self.identifier = identifier
        self.name = name
        self.connectionState = connectionState
    }
}

public enum DeviceSelectionFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case message(String)

    public var description: String {
        switch self {
            case let .message(message): message
        }
    }
}

/// Selects one physical iOS-family device from `devicectl`'s typed JSON schema.
public struct DeviceSelector: Sendable {
    public init() {}

    public func select(from data: Data, filter: String?) throws -> DeviceSelection {
        let list: DeviceControlList
        do {
            list = try JSONDecoder().decode(DeviceControlList.self, from: data)
        } catch {
            throw DeviceSelectionFailure.message(
                "couldn't read devicectl's device list (\(error)). " +
                    "Run `xcrun devicectl list devices` to check your setup.",
            )
        }
        let wanted = filter?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let candidates = (list.result?.devices ?? []).compactMap { device -> DeviceSelection? in
            let hardware = device.properties?.hardware
            guard ["ios", "ipados"].contains(hardware?.platform?.lowercased() ?? ""),
                  hardware?.reality?.lowercased() == "physical"
            else {
                return nil
            }
            let identifier = nonempty(device.identifier) ?? nonempty(hardware?.udid)
            guard let identifier else { return nil }
            let name = nonempty(device.properties?.state?.name) ?? "(unnamed)"
            let udid = hardware?.udid ?? ""
            if wanted.isEmpty == false,
               [name.lowercased(), udid.lowercased(), identifier.lowercased()]
               .contains(wanted) == false
            {
                return nil
            }
            return DeviceSelection(
                identifier: identifier,
                name: name,
                connectionState: nonempty(device.properties?.connection?.state) ?? "unknown",
            )
        }

        guard candidates.isEmpty == false else {
            if let filter, wanted.isEmpty == false {
                throw DeviceSelectionFailure.message(
                    "no physical iOS device matching \"\(filter)\". " +
                        "Run `xcrun devicectl list devices` to see what's paired.",
                )
            }
            throw DeviceSelectionFailure.message(
                "no physical iOS device found. Pair or plug in an iPhone, unlock it, " +
                    "and trust this Mac.",
            )
        }
        guard candidates.count == 1 else {
            let listing = candidates.map {
                "  - \($0.name) (\($0.identifier)) [\($0.connectionState)]"
            }.joined(separator: "\n")
            throw DeviceSelectionFailure.message(
                "multiple physical iOS devices; pass --device <name|udid>:\n\(listing)",
            )
        }
        return candidates[0]
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        return value
    }
}

private struct DeviceControlList: Decodable {
    let result: Result?

    struct Result: Decodable {
        let devices: [Device]?
    }

    struct Device: Decodable {
        let identifier: String?
        let properties: Properties?
    }

    struct Properties: Decodable {
        let hardware: Hardware?
        let connection: Connection?
        let state: State?
    }

    struct Hardware: Decodable {
        let platform: String?
        let reality: String?
        let udid: String?
    }

    struct Connection: Decodable {
        let state: String?
    }

    struct State: Decodable {
        let name: String?
    }
}
