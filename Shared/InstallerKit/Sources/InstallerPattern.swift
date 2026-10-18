import Foundation

/// Anchored wire-format patterns shared by signed build metadata and catalog validation.
enum InstallerPattern: String {
    case appID = #"\A[a-z][a-z0-9-]{0,63}\z"#
    case bundleIdentifier = #"\A[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z"#
    case channel = #"\A(main|pr-[1-9][0-9]*)\z"#
    case repositoryURL = #"\Ahttps://github.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z"#
    case revision = #"\A[0-9a-f]{40}\z"#
    case version = #"\A[0-9]+(?:\.[0-9]+){0,2}\z"#

    func matches(_ value: String) -> Bool {
        value.range(of: rawValue, options: .regularExpression) != nil
    }
}
