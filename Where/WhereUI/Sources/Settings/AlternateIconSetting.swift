import UIKit

/// The slice of `UIApplication` the icon picker needs, behind a protocol so
/// tests can drive selection without touching the real springboard — the live
/// API pops a system alert and only works inside a running app.
///
/// `WhereCore` can't import UIKit, so this seam lives in `WhereUI`. The member
/// names match `UIApplication` exactly, so it conforms with no extra code.
@MainActor
protocol AlternateIconSetting {
    var supportsAlternateIcons: Bool { get }
    var alternateIconName: String? { get }
    func setAlternateIconName(_ alternateIconName: String?) async throws
}

extension UIApplication: AlternateIconSetting {}
