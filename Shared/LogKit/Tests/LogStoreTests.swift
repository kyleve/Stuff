import Foundation
@_spi(Testing) import LogKit
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

@Test
func cancelledChangesStreamUnregistersObserver() async {
    let store = LogStore()
    store.record(entry("before"))

    do {
        var iterator = store.changes().makeAsyncIterator()
        _ = await iterator.next()
    }

    store.record(entry("after-cancel"))

    var iterator = store.changes().makeAsyncIterator()
    let snapshot = await iterator.next()
    #expect(snapshot?.map(\.message) == ["before", "after-cancel"])
}

@Test
func changesNotifiesMultipleObservers() async {
    let store = LogStore()
    store.record(entry("a"))

    var firstObserver = store.changes().makeAsyncIterator()
    var secondObserver = store.changes().makeAsyncIterator()

    let firstInitial = await firstObserver.next()
    let secondInitial = await secondObserver.next()
    #expect(firstInitial?.map(\.message) == ["a"])
    #expect(secondInitial?.map(\.message) == ["a"])

    store.record(entry("b"))
    let firstUpdate = await firstObserver.next()
    let secondUpdate = await secondObserver.next()
    #expect(firstUpdate?.map(\.message) == ["a", "b"])
    #expect(secondUpdate?.map(\.message) == ["a", "b"])
}

@Test
func changesDeliversMonotonicSnapshotsForSequentialRecords() async {
    let store = LogStore()
    var iterator = store.changes().makeAsyncIterator()
    _ = await iterator.next()

    var previousCount = 0
    for index in 0 ..< 10 {
        store.record(entry("\(index)"))
        if let snapshot = await iterator.next() {
            #expect(snapshot.count == previousCount + 1)
            previousCount = snapshot.count
        }
    }
}

@Test
func changesDeliversFinalSnapshotAfterConcurrentRecords() async {
    let store = LogStore()
    var iterator = store.changes().makeAsyncIterator()
    _ = await iterator.next()

    let recordCount = 50
    await withTaskGroup(of: Void.self) { group in
        for index in 0 ..< recordCount {
            group.addTask {
                store.record(entry("\(index)"))
            }
        }
    }

    var lastSnapshot: [LogEntry]?
    while let snapshot = await iterator.next() {
        lastSnapshot = snapshot
        if snapshot.count == recordCount {
            break
        }
    }
    #expect(lastSnapshot?.count == recordCount)
}

@Test
func changesInitialYieldReflectsPreRegistrationSnapshot() async {
    let store = LogStore()

    let initialCount = await withTaskGroup(of: Int.self) { group in
        group.addTask {
            var iterator = store.changes().makeAsyncIterator()
            let initial = await iterator.next()
            return initial?.count ?? -1
        }
        group.addTask {
            for index in 0 ..< 10 {
                store.record(entry("\(index)"))
            }
            return store.snapshot().count
        }

        var counts: [Int] = []
        for await count in group {
            counts.append(count)
        }
        return counts.first(where: { $0 >= 0 }) ?? -1
    }

    #expect(initialCount == 0)
}
