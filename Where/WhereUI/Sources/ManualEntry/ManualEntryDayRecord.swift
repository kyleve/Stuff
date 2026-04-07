import Foundation
import WhereCore

public struct ManualEntryDayRecord: Equatable, Sendable, Identifiable {
    public let record: ManualEntryRecord
    public let changesDayOutcome: Bool

    public init(
        record: ManualEntryRecord,
        changesDayOutcome: Bool,
    ) {
        self.record = record
        self.changesDayOutcome = changesDayOutcome
    }

    public var id: UUID {
        record.id
    }
}
