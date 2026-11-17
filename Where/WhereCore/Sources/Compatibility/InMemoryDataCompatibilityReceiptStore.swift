/// In-memory counterpart for demo, preview, and test composition. Uses ordinary verification.
@MainActor
public final class InMemoryDataCompatibilityReceiptStore: DataCompatibilityReceiptStoring {
    private var receipt: DataCompatibilityReceipt?

    public init(receipt: DataCompatibilityReceipt?) {
        self.receipt = receipt
    }

    public func load() throws -> DataCompatibilityReceipt? {
        receipt
    }

    public func save(_ receipt: DataCompatibilityReceipt) throws {
        self.receipt = receipt
    }
}
