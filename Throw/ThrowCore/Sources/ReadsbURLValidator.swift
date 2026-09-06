import Darwin
import Foundation

enum ReadsbJSONEndpoint: String {
    case aircraft = "aircraft.json"
    case receiver = "receiver.json"

    init?(url: URL) {
        self.init(rawValue: url.lastPathComponent)
    }
}

public enum ReadsbURLValidator {
    public static func validate(_ url: URL) throws -> URL {
        try validate(url, endpoint: .aircraft)
    }

    static func validateRedirectTarget(
        _ url: URL,
        endpoint: ReadsbJSONEndpoint,
    ) throws -> URL {
        try validate(url, endpoint: endpoint)
    }

    private static func validate(
        _ url: URL,
        endpoint: ReadsbJSONEndpoint,
    ) throws -> URL {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              host.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.fragment == nil,
              url.lastPathComponent == endpoint.rawValue,
              scheme == "http" || scheme == "https"
        else {
            throw ThrowValidationError.invalidURL
        }

        if scheme == "http", isLocalNetworkHost(host) == false {
            throw ThrowValidationError.invalidURL
        }
        return url
    }

    public static func receiverJSONURL(for aircraftJSONURL: URL) throws -> URL {
        let validated = try validate(aircraftJSONURL)
        guard var components = URLComponents(url: validated, resolvingAgainstBaseURL: false) else {
            throw ThrowValidationError.invalidURL
        }
        var pathComponents = components.path.split(separator: "/").map(String.init)
        guard pathComponents.last == "aircraft.json" else {
            throw ThrowValidationError.invalidURL
        }
        pathComponents[pathComponents.count - 1] = "receiver.json"
        components.path = "/" + pathComponents.joined(separator: "/")
        guard let result = components.url else {
            throw ThrowValidationError.invalidURL
        }
        return result
    }

    public static func isLocalNetworkHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".localhost") || normalized
            .hasSuffix(".local")
        {
            return true
        }
        if isLocalIPv6Literal(normalized) {
            return true
        }

        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        var octets: [Int] = []
        octets.reserveCapacity(4)
        for component in components {
            guard component.isEmpty == false,
                  component.allSatisfy(\.isNumber),
                  let octet = Int(component),
                  (0 ... 255).contains(octet)
            else {
                return false
            }
            octets.append(octet)
        }
        guard octets.count == 4 else {
            return false
        }
        switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254):
                return true
            case (172, 16 ... 31):
                return true
            case (_, _):
                return false
        }
    }

    private static func isLocalIPv6Literal(_ host: String) -> Bool {
        let literal = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        var address = in6_addr()
        guard inet_pton(AF_INET6, literal, &address) == 1 else { return false }
        let bytes = withUnsafeBytes(of: address) { Array($0) }
        let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
        let isUniqueLocal = (bytes[0] & 0xFE) == 0xFC
        let isLinkLocal = bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80
        return isLoopback || isUniqueLocal || isLinkLocal
    }
}
