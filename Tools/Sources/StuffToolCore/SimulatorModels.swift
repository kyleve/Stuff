import Foundation

public struct SimctlDeviceList: Decodable, Equatable, Sendable {
    public struct Device: Decodable, Equatable, Sendable {
        public let name: String
        public let udid: String
        public let state: String

        public init(name: String, udid: String, state: String) {
            self.name = name
            self.udid = udid
            self.state = state
        }
    }

    public let devices: [String: [Device]]

    public init(devices: [String: [Device]]) {
        self.devices = devices
    }

    public func devices(runtime: String, named name: String) -> [Device] {
        devices[runtime, default: []].filter { $0.name == name }
    }

    public var allDevices: [Device] {
        devices.keys.sorted().flatMap { devices[$0, default: []] }
    }
}

public struct SimctlDeviceTypes: Decodable, Equatable, Sendable {
    public struct DeviceType: Decodable, Equatable, Sendable {
        public let name: String
        public let identifier: String
    }

    public let devicetypes: [DeviceType]
}

public struct SimctlRuntimes: Decodable, Equatable, Sendable {
    public struct Runtime: Decodable, Equatable, Sendable {
        public let identifier: String
        public let isAvailable: Bool
    }

    public let runtimes: [Runtime]
}

public enum SimulatorSelection: Equatable, Sendable {
    case missing
    case selected(udid: String, ambiguousCount: Int)

    public static func select(_ devices: [SimctlDeviceList.Device]) -> Self {
        guard let first = devices.first else { return .missing }
        return .selected(udid: first.udid, ambiguousCount: devices.count)
    }
}
