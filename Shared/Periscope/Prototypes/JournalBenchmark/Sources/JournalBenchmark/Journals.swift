import CoreData
import Foundation
import GRDB
import SQLite3
import SwiftData

/// One journal candidate: appends length-prefixed/row entries synchronously,
/// and can count what a *fresh* open recovers (the durability check).
protocol JournalStore {
    /// Append one entry. Must be safe to call from multiple threads.
    func append(seq: Int, payload: Data) throws
    /// Commit anything a batched variant is still holding (end of run).
    func finish() throws
}

enum Variant: String, CaseIterable {
    case file
    case fileFsync = "file-fsync"
    case sqliteNormal = "sqlite-normal"
    case sqliteFull = "sqlite-full"
    case grdb
    case coreData = "coredata"
    case coreDataBatched = "coredata-batched"
    case swiftData = "swiftdata"
    case swiftDataBatched = "swiftdata-batched"

    func make(at url: URL) throws -> JournalStore {
        switch self {
            case .file: try FileJournal(url: url, fsyncEachAppend: false)
            case .fileFsync: try FileJournal(url: url, fsyncEachAppend: true)
            case .sqliteNormal: try SQLiteJournal(url: url, synchronous: "NORMAL")
            case .sqliteFull: try SQLiteJournal(url: url, synchronous: "FULL")
            case .grdb: try GRDBJournal(url: url)
            case .coreData: try CoreDataJournal(url: url, saveEvery: 1)
            case .coreDataBatched: try CoreDataJournal(url: url, saveEvery: 100)
            case .swiftData: try SwiftDataJournal(url: url, saveEvery: 1)
            case .swiftDataBatched: try SwiftDataJournal(url: url, saveEvery: 100)
        }
    }

    /// Open the journal fresh (as the next launch would) and count entries.
    func recoveredCount(at url: URL) throws -> Int {
        switch self {
            case .file, .fileFsync: try FileJournal.recover(url: url)
            case .sqliteNormal, .sqliteFull: try SQLiteJournal.recover(url: url)
            case .grdb: try GRDBJournal.recover(url: url)
            case .coreData, .coreDataBatched: try CoreDataJournal.recover(url: url)
            case .swiftData, .swiftDataBatched: try SwiftDataJournal.recover(url: url)
        }
    }
}

// MARK: - Append-only file

final class FileJournal: JournalStore {
    private let fd: Int32
    private let fsyncEachAppend: Bool
    private let lock = NSLock()

    init(url: URL, fsyncEachAppend: Bool) throws {
        fd = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard fd >= 0 else { throw Failure("open failed: \(errno)") }
        self.fsyncEachAppend = fsyncEachAppend
    }

    func append(seq: Int, payload: Data) throws {
        var buffer = Data(capacity: payload.count + 12)
        withUnsafeBytes(of: UInt32(payload.count).littleEndian) { buffer.append(contentsOf: $0) }
        withUnsafeBytes(of: Int64(seq).littleEndian) { buffer.append(contentsOf: $0) }
        buffer.append(payload)
        lock.lock()
        defer { lock.unlock() }
        let written = buffer.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == buffer.count else { throw Failure("short write") }
        if fsyncEachAppend {
            fsync(fd)
        }
    }

    func finish() throws {}

    static func recover(url: URL) throws -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        var count = 0
        var offset = 0
        while offset + 12 <= data.count {
            let length = data.subdata(in: offset ..< offset + 4)
                .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
            let end = offset + 12 + Int(length)
            guard end <= data.count else { break } // torn tail
            count += 1
            offset = end
        }
        return count
    }
}

// MARK: - Raw SQLite (WAL)

final class SQLiteJournal: JournalStore {
    private let db: OpaquePointer
    private let insert: OpaquePointer
    private let lock = NSLock()

    init(url: URL, synchronous: String) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw Failure("sqlite open failed")
        }
        db = handle
        try Self.exec(db, "PRAGMA journal_mode=WAL")
        try Self.exec(db, "PRAGMA synchronous=\(synchronous)")
        try Self.exec(
            db,
            "CREATE TABLE IF NOT EXISTS journal(seq INTEGER PRIMARY KEY, payload BLOB NOT NULL)",
        )
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "INSERT INTO journal(seq, payload) VALUES(?, ?)",
            -1,
            &statement,
            nil,
        ) == SQLITE_OK,
            let statement
        else { throw Failure("prepare failed") }
        insert = statement
    }

    func append(seq: Int, payload: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        sqlite3_bind_int64(insert, 1, Int64(seq))
        _ = payload.withUnsafeBytes {
            sqlite3_bind_blob(
                insert,
                2,
                $0.baseAddress,
                Int32($0.count),
                unsafeBitCast(-1, to: sqlite3_destructor_type.self),
            )
        }
        guard sqlite3_step(insert) == SQLITE_DONE else { throw Failure("insert failed") }
        sqlite3_reset(insert)
        sqlite3_clear_bindings(insert)
    }

    func finish() throws {}

    static func recover(url: URL) throws -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else { return 0 }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM journal", -1, &statement, nil) ==
            SQLITE_OK
        else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static func exec(_ db: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw Failure("exec failed: \(sql)")
        }
    }
}

// MARK: - GRDB

final class GRDBJournal: JournalStore {
    private let queue: DatabaseQueue

    init(url: URL) throws {
        var configuration = Configuration()
        configuration.journalMode = .wal
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        queue = try DatabaseQueue(path: url.path, configuration: configuration)
        try queue.write { db in
            try db
                .execute(
                    sql: "CREATE TABLE IF NOT EXISTS journal(seq INTEGER PRIMARY KEY, payload BLOB NOT NULL)",
                )
        }
    }

    func append(seq: Int, payload: Data) throws {
        try queue.write { db in
            try db.execute(
                sql: "INSERT INTO journal(seq, payload) VALUES(?, ?)",
                arguments: [seq, payload],
            )
        }
    }

    func finish() throws {}

    static func recover(url: URL) throws -> Int {
        let queue = try DatabaseQueue(path: url.path)
        return try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM journal") ?? 0
        }
    }
}

// MARK: - Core Data

final class CoreDataJournal: JournalStore {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext
    private let saveEvery: Int
    private var pending = 0

    static let model: NSManagedObjectModel = {
        let entity = NSEntityDescription()
        entity.name = "Entry"
        let seq = NSAttributeDescription()
        seq.name = "seq"
        seq.attributeType = .integer64AttributeType
        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        entity.properties = [seq, payload]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }()

    init(url: URL, saveEvery: Int) throws {
        container = NSPersistentContainer(name: "Journal", managedObjectModel: Self.model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.newBackgroundContext()
        self.saveEvery = saveEvery
    }

    func append(seq: Int, payload: Data) throws {
        var thrown: Error?
        context.performAndWait {
            let entry = NSManagedObject(
                entity: Self.model.entitiesByName["Entry"]!,
                insertInto: context,
            )
            entry.setValue(seq, forKey: "seq")
            entry.setValue(payload, forKey: "payload")
            pending += 1
            if pending >= saveEvery {
                do {
                    try context.save()
                    pending = 0
                } catch {
                    thrown = error
                }
            }
        }
        if let thrown { throw thrown }
    }

    func finish() throws {
        var thrown: Error?
        context.performAndWait {
            if context.hasChanges {
                do { try context.save() } catch { thrown = error }
            }
        }
        if let thrown { throw thrown }
    }

    static func recover(url: URL) throws -> Int {
        let container = NSPersistentContainer(name: "Journal", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Entry")
        return try container.newBackgroundContext().performAndWait {
            try container.newBackgroundContext().count(for: request)
        }
    }
}

// MARK: - SwiftData

@Model
final class SDEntry {
    var seq: Int
    var payload: Data

    init(seq: Int, payload: Data) {
        self.seq = seq
        self.payload = payload
    }
}

final class SwiftDataJournal: JournalStore {
    private let container: ModelContainer
    private let context: ModelContext
    private let saveEvery: Int
    private var pending = 0
    private let lock = NSLock()

    init(url: URL, saveEvery: Int) throws {
        let configuration = ModelConfiguration(url: url)
        container = try ModelContainer(for: SDEntry.self, configurations: configuration)
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.saveEvery = saveEvery
    }

    func append(seq: Int, payload: Data) throws {
        // ModelContext is not thread-safe; exclusive access via lock is the
        // most charitable synchronous shape available to a journal.
        lock.lock()
        defer { lock.unlock() }
        context.insert(SDEntry(seq: seq, payload: payload))
        pending += 1
        if pending >= saveEvery {
            try context.save()
            pending = 0
        }
    }

    func finish() throws {
        lock.lock()
        defer { lock.unlock() }
        if context.hasChanges {
            try context.save()
        }
    }

    static func recover(url: URL) throws -> Int {
        let configuration = ModelConfiguration(url: url)
        let container = try ModelContainer(for: SDEntry.self, configurations: configuration)
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<SDEntry>())
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
