import Foundation
import LogKit
import Testing

private func entry(_ message: String, level: LogLevel = .info) -> LogEntry {
    LogEntry(level: level, subsystem: "test", category: "test", message: message)
}

@Test
func recordsAppendInOrder() {
    let store = LogStore()
    store.record(entry("a"))
    store.record(entry("b"))
    store.record(entry("c"))

    #expect(store.snapshot().map(\.message) == ["a", "b", "c"])
}

@Test
func evictsOldestPastCapacity() {
    let store = LogStore(capacity: 3)
    for index in 0 ..< 5 {
        store.record(entry("\(index)"))
    }

    #expect(store.snapshot().map(\.message) == ["2", "3", "4"])
}

@Test
func clearEmptiesTheBuffer() {
    let store = LogStore()
    store.record(entry("a"))
    store.clear()

    #expect(store.snapshot().isEmpty)
}

@Test
func changesYieldsInitialThenUpdates() async {
    let store = LogStore()
    store.record(entry("initial"))

    var iterator = store.changes().makeAsyncIterator()

    let first = await iterator.next()
    #expect(first?.map(\.message) == ["initial"])

    store.record(entry("second"))
    let second = await iterator.next()
    #expect(second?.map(\.message) == ["initial", "second"])

    store.clear()
    let third = await iterator.next()
    #expect(third?.isEmpty == true)
}
