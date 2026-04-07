import Foundation

public protocol ManualLogEntryRepository: Sendable {
    func availableYears() async -> [Int]
    func entries(in year: Int) async -> [ManualLogEntry]
    func save(_ entry: ManualLogEntry) async
    func save(_ entries: [ManualLogEntry]) async
    func delete(id: UUID) async
    func removeAll() async
}
