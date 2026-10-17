import Foundation
import SwiftData

@Model
final class FlagOverride {
    @Attribute(.unique) var key: String
    var value: Data

    init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}
