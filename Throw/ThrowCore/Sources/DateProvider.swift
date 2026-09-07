import Foundation

public protocol DateProvider: Sendable {
    func now() -> Date
}

public struct SystemDateProvider: DateProvider {
    public init() {}

    public func now() -> Date {
        Date()
    }
}
