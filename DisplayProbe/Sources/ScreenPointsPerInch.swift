import ObjectiveC
import UIKit

/// Reads the personal diagnostic app's one permitted private UIScreen getter.
/// Validate its Objective-C ABI before calling it; never substitute an estimated density.
enum ScreenPointsPerInch: Equatable {
    case available(Double)
    case unavailable
    case incompatibleSignature
    case invalidValue

    @MainActor
    static func read(from screen: UIScreen) -> Self {
        let selector = NSSelectorFromString("_pointsPerInch")
        guard let method = class_getInstanceMethod(type(of: screen), selector) else {
            return .unavailable
        }
        guard method_getNumberOfArguments(method) == 2 else {
            return .incompatibleSignature
        }
        let returnType = method_copyReturnType(method)
        defer { free(returnType) }
        // Observed encoding on the installed runtime: d16@0:8 (Double, self, _cmd).
        guard String(cString: returnType) == "d" else { return .incompatibleSignature }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Double
        let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
        let value = getter(screen, selector)
        guard value.isFinite, value > 0 else { return .invalidValue }
        return .available(value)
    }

    var description: String {
        switch self {
            case let .available(value):
                "\(DisplayReading.number(CGFloat(value))) pt/in"
            case .unavailable:
                "Unavailable"
            case .incompatibleSignature:
                "Unavailable · incompatible SPI signature"
            case .invalidValue:
                "Unavailable · invalid SPI value"
        }
    }
}
