import Foundation

/// Names used at setup and when resolving historical installations on another device.
public enum RecordingDeviceName {
    /// Apple’s CoreSimulator device profiles supply the compatible hardware identifiers
    /// for each product, including Wi-Fi and cellular variants of the same iPad.
    public static func modelLabel(for identifier: String) -> String {
        switch identifier {
            case "iPad13,18", "iPad13,19": "iPad (10th generation)"
            case "iPad6,11", "iPad6,12": "iPad (5th generation)"
            case "iPad7,5", "iPad7,6": "iPad (6th generation)"
            case "iPad7,11", "iPad7,12": "iPad (7th generation)"
            case "iPad11,6", "iPad11,7": "iPad (8th generation)"
            case "iPad12,1", "iPad12,2": "iPad (9th generation)"
            case "iPad15,7", "iPad15,8": "iPad (A16)"
            case "iPad11,3", "iPad11,4": "iPad Air (3rd generation)"
            case "iPad13,1", "iPad13,2": "iPad Air (4th generation)"
            case "iPad13,16", "iPad13,17": "iPad Air (5th generation)"
            case "iPad14,8", "iPad14,9": "iPad Air 11-inch (M2)"
            case "iPad15,3", "iPad15,4": "iPad Air 11-inch (M3)"
            case "iPad16,8", "iPad16,9": "iPad Air 11-inch (M4)"
            case "iPad14,10", "iPad14,11": "iPad Air 13-inch (M2)"
            case "iPad15,5", "iPad15,6": "iPad Air 13-inch (M3)"
            case "iPad16,10", "iPad16,11": "iPad Air 13-inch (M4)"
            case "iPad5,3", "iPad5,4": "iPad Air 2"
            case "iPad7,3", "iPad7,4": "iPad Pro (10.5-inch)"
            case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": "iPad Pro (11-inch) (1st generation)"
            case "iPad8,10", "iPad8,9": "iPad Pro (11-inch) (2nd generation)"
            case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": "iPad Pro (11-inch) (3rd generation)"
            case "iPad14,3", "iPad14,4": "iPad Pro (11-inch) (4th generation)"
            case "iPad6,7", "iPad6,8": "iPad Pro (12.9-inch) (1st generation)"
            case "iPad7,1", "iPad7,2": "iPad Pro (12.9-inch) (2nd generation)"
            case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": "iPad Pro (12.9-inch) (3rd generation)"
            case "iPad8,11", "iPad8,12": "iPad Pro (12.9-inch) (4th generation)"
            case "iPad13,10", "iPad13,11", "iPad13,8", "iPad13,9": "iPad Pro (12.9-inch) (5th generation)"
            case "iPad14,5", "iPad14,6": "iPad Pro (12.9-inch) (6th generation)"
            case "iPad6,3", "iPad6,4": "iPad Pro (9.7-inch)"
            case "iPad16,3", "iPad16,4": "iPad Pro 11-inch (M4)"
            case "iPad17,1", "iPad17,2": "iPad Pro 11-inch (M5)"
            case "iPad16,5", "iPad16,6": "iPad Pro 13-inch (M4)"
            case "iPad17,3", "iPad17,4": "iPad Pro 13-inch (M5)"
            case "iPad11,1", "iPad11,2": "iPad mini (5th generation)"
            case "iPad14,1", "iPad14,2": "iPad mini (6th generation)"
            case "iPad16,1", "iPad16,2": "iPad mini (A17 Pro)"
            case "iPad19,1", "iPad19,2": "iPad mini (A20 Pro)"
            case "iPad5,1", "iPad5,2": "iPad mini 4"
            case "iPhone12,5": "iPhone 11 Pro Max"
            case "iPhone12,3": "iPhone 11 Pro"
            case "iPhone12,1": "iPhone 11"
            case "iPhone13,4": "iPhone 12 Pro Max"
            case "iPhone13,3": "iPhone 12 Pro"
            case "iPhone13,1": "iPhone 12 mini"
            case "iPhone13,2": "iPhone 12"
            case "iPhone14,3": "iPhone 13 Pro Max"
            case "iPhone14,2": "iPhone 13 Pro"
            case "iPhone14,4": "iPhone 13 mini"
            case "iPhone14,5": "iPhone 13"
            case "iPhone14,8": "iPhone 14 Plus"
            case "iPhone15,3": "iPhone 14 Pro Max"
            case "iPhone15,2": "iPhone 14 Pro"
            case "iPhone14,7": "iPhone 14"
            case "iPhone15,5": "iPhone 15 Plus"
            case "iPhone16,2": "iPhone 15 Pro Max"
            case "iPhone16,1": "iPhone 15 Pro"
            case "iPhone15,4": "iPhone 15"
            case "iPhone17,4": "iPhone 16 Plus"
            case "iPhone17,2": "iPhone 16 Pro Max"
            case "iPhone17,1": "iPhone 16 Pro"
            case "iPhone17,3": "iPhone 16"
            case "iPhone17,5": "iPhone 16e"
            case "iPhone18,2": "iPhone 17 Pro Max"
            case "iPhone18,1": "iPhone 17 Pro"
            case "iPhone18,3": "iPhone 17"
            case "iPhone18,5": "iPhone 17e"
            case "iPhone19,3", "iPhone19,7": "iPhone 18 Pro Max"
            case "iPhone19,2": "iPhone 18 Pro"
            case "iPhone8,2": "iPhone 6s Plus"
            case "iPhone8,1": "iPhone 6s"
            case "iPhone9,2", "iPhone9,4": "iPhone 7 Plus"
            case "iPhone9,1", "iPhone9,3": "iPhone 7"
            case "iPhone10,2", "iPhone10,5": "iPhone 8 Plus"
            case "iPhone10,1", "iPhone10,4": "iPhone 8"
            case "iPhone18,4": "iPhone Air"
            case "iPhone19,4": "iPhone Duo"
            case "iPhone8,4": "iPhone SE (1st generation)"
            case "iPhone12,8": "iPhone SE (2nd generation)"
            case "iPhone14,6": "iPhone SE (3rd generation)"
            case "iPhone10,3", "iPhone10,6": "iPhone X"
            case "iPhone11,4", "iPhone11,6": "iPhone Xs Max"
            case "iPhone11,2": "iPhone Xs"
            case "iPhone11,8": "iPhone Xʀ"
            default: identifier
        }
    }

    /// Accepting the suggested name and clearing the name both select the model fallback.
    public static func normalizedNickname(_ nickname: String?, fallback: String) -> String? {
        guard let value = nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value != fallback else { return nil }
        return value
    }

    public static func displayName(nickname: String?, fallback: String) -> String {
        normalizedNickname(nickname, fallback: fallback) ?? fallback
    }
}
