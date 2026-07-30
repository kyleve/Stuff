/// An optional grid override for a screen whose automatic graph position needs adjustment.
public struct FlyoverPosition: Equatable, Hashable, Sendable {
    public let column: Int
    public let row: Int

    public init(column: Int, row: Int) {
        precondition(column >= 0, "A Flyover column must not be negative.")
        precondition(row >= 0, "A Flyover row must not be negative.")
        self.column = column
        self.row = row
    }
}
