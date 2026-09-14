import Foundation
@testable import PortholeRuntime
import Testing

struct PortholeObjectStoreTests {
    @Test func repeatedResultsStayWithinTotalCapacityWithoutEvictingExplicitRoots() throws {
        var store = PortholeObjectStore(capacity: 3)
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let first = try store.retain(
            "service",
            typeName: "String",
            scope: scope,
            retention: .scope,
            operationID: nil,
        )
        let second = try store.retain(
            "store",
            typeName: "String",
            scope: scope,
            retention: .scope,
            operationID: nil,
        )
        for index in 0 ..< 100 {
            let latest = try store.retain(
                index,
                typeName: "Int",
                scope: scope,
                retention: .results,
                operationID: nil,
            )
            #expect(Set(store.references(in: scope).map(\.id)) == [first.id, second.id, latest.id])
        }
    }

    @Test func boundedPoolsEvictOldSnapshotsAndChildrenButKeepScopeRoots() throws {
        var store = PortholeObjectStore(capacity: 10)
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let root = try store.retain(
            "services",
            typeName: "String",
            scope: scope,
            retention: .scope,
            operationID: nil,
        )
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "captures"),
            maximumCount: 1,
        )
        let first = try store.retain(
            "old year",
            typeName: "String",
            scope: scope,
            retention: pool,
            operationID: nil,
        )
        let child = try store.retainChild(
            "day",
            typeName: "String",
            parent: first,
            key: .init(rawValue: "input"),
            operationID: nil,
        )
        let latest = try store.retain(
            "new year",
            typeName: "String",
            scope: scope,
            retention: pool,
            operationID: nil,
        )
        #expect(Set(store.references(in: scope).map(\.id)) == [root.id, latest.id])
        #expect(throws: PortholeError.unknownObject) {
            try store.entry(for: first, operationID: nil)
        }
        #expect(throws: PortholeError.unknownObject) {
            try store.entry(for: child, operationID: nil)
        }
    }

    @Test func repeatedChildReadsReuseHandlesAndReleaseInvalidatesTheFamily() throws {
        var store = PortholeObjectStore(capacity: 4)
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let parent = try store.retain(
            "year",
            typeName: "String",
            scope: scope,
            retention: .results,
            operationID: nil,
        )
        let child = try store.retainChild(
            "day",
            typeName: "String",
            parent: parent,
            key: .init(rawValue: "input"),
            operationID: nil,
        )
        for _ in 0 ..< 100 {
            #expect(try store.retainChild(
                "day",
                typeName: "String",
                parent: parent,
                key: .init(rawValue: "input"),
                operationID: nil,
            ) == child)
        }
        #expect(store.references(in: scope).count == 2)
        try store.release(parent)
        #expect(store.references(in: scope).isEmpty)
        #expect(throws: PortholeError.unknownObject) {
            try store.entry(for: child, operationID: nil)
        }
        #expect(throws: PortholeError.unknownObject) { try store.retainChild(
            "day",
            typeName: "String",
            parent: parent,
            key: .init(rawValue: "input"),
            operationID: nil,
        ) }
    }

    @Test func leasesProtectArgumentsAndParentsUntilNativeWorkFinishes() throws {
        var store = PortholeObjectStore(capacity: 3)
        let scope = PortholeScopeToken(id: .init(rawValue: "app"), generation: UUID())
        let pool = PortholeObjectRetention.bounded(
            pool: .init(rawValue: "captures"),
            maximumCount: 1,
        )
        let parent = try store.retain(
            "year",
            typeName: "String",
            scope: scope,
            retention: pool,
            operationID: nil,
        )
        let child = try store.retainChild(
            "day",
            typeName: "String",
            parent: parent,
            key: .init(rawValue: "input"),
            operationID: nil,
        )
        let operationID = UUID()
        try store.lease([child], operationID: operationID)
        #expect(throws: PortholeError.capacityExceeded) { try store.retain(
            "next year",
            typeName: "String",
            scope: scope,
            retention: pool,
            operationID: nil,
        ) }
        #expect(throws: PortholeError.operationInProgress) { try store.release(parent) }
        store.finish(operationID: operationID)
        _ = try store.retain(
            "next year",
            typeName: "String",
            scope: scope,
            retention: pool,
            operationID: nil,
        )
        #expect(throws: PortholeError.unknownObject) {
            try store.entry(for: child, operationID: nil)
        }
    }
}
