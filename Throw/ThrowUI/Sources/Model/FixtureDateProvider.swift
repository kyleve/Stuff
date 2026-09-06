import Foundation
import ThrowCore

struct FixtureDateProvider: DateProvider {
    let date: Date

    func now() -> Date {
        date
    }
}
