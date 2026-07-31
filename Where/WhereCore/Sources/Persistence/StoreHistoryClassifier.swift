import Foundation
import SwiftData

/// Separates this store instance's transactions from writes made elsewhere.
///
/// `NSPersistentStoreRemoteChange` is a write notification, not an
/// external-origin guarantee. Every writer context owned by `SwiftDataStore`
/// carries `localAuthor`; history after a checkpoint is external when at least
/// one transaction has a different author. Each operation uses a fresh
/// `ModelContext`, keeping this value stateless and safe to use from the
/// store's long-lived observation task.
struct StoreHistoryClassifier {
    struct Classification {
        let latestToken: DefaultHistoryToken?
        let containsExternalTransaction: Bool
    }

    let container: ModelContainer
    let localAuthor: String

    /// Returns the newest history token, used as the observation checkpoint.
    func checkpoint() throws -> DefaultHistoryToken? {
        let context = ModelContext(container)
        var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
            sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try context.fetchHistory(descriptor).first?.token
    }

    /// Classifies every transaction after `token` and advances the checkpoint.
    func classify(after token: DefaultHistoryToken?) throws -> Classification {
        let context = ModelContext(container)
        var descriptor = if let token {
            HistoryDescriptor<DefaultHistoryTransaction>(
                predicate: #Predicate { $0.token > token },
            )
        } else {
            HistoryDescriptor<DefaultHistoryTransaction>()
        }
        descriptor.sortBy = [SortDescriptor(\.transactionIdentifier, order: .forward)]
        let transactions = try context.fetchHistory(descriptor)
        return Classification(
            latestToken: transactions.last?.token ?? token,
            containsExternalTransaction: transactions.contains { $0.author != localAuthor },
        )
    }
}
