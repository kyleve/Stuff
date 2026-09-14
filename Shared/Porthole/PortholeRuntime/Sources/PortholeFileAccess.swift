import Darwin
import Foundation
import PortholeCore

/// Opens each path component relative to a retained directory descriptor and never follows links.
struct PortholeFileAccess {
    struct Entry {
        let name: String
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let bytes: Int64
    }

    let root: URL
    let components: [String]
    let maximumBytes: Int

    func validate() throws {
        try withParent { parent, leaf in
            guard let leaf else { return }
            var info = stat()
            if fstatat(parent, leaf, &info, AT_SYMLINK_NOFOLLOW) != 0 {
                guard errno == ENOENT else { throw failure() }
                return
            }
            guard info.st_mode & S_IFMT != S_IFLNK else { throw linkError }
        }
    }

    func read() throws -> Data {
        try withParent { parent, leaf in
            guard let leaf else { throw PortholeError.invalidArguments("Select a regular file") }
            return try read(parent: parent, leaf: leaf)
        }
    }

    func entries(maximumCount: Int) throws -> [Entry] {
        try withParent { parent, leaf in
            let descriptor = leaf.map { openat(
                parent,
                $0,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
            ) } ?? dup(parent)
            guard descriptor >= 0 else { throw failure() }
            guard let stream = fdopendir(descriptor)
            else { let error = failure(); close(descriptor); throw error }
            defer { closedir(stream) }
            var result: [Entry] = []
            while true {
                try Task.checkCancellation()
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw failure() }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0
                        .withMemoryRebound(
                            to: CChar.self,
                            capacity: Int(entry.pointee.d_namlen) + 1,
                        ) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                guard result.count < maximumCount else { throw PortholeError.capacityExceeded }
                var info = stat()
                guard fstatat(descriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0
                else { throw failure() }
                result.append(Entry(
                    name: name,
                    isDirectory: info.st_mode & S_IFMT == S_IFDIR,
                    isSymbolicLink: info.st_mode & S_IFMT == S_IFLNK,
                    bytes: info.st_size,
                ))
            }
            return result.sorted { $0.name < $1.name }
        }
    }

    func write(_ data: Data, expected: String?, hash: (Data) -> String) throws {
        try withParent { parent, leaf in
            guard let leaf else { throw PortholeError.invalidArguments("Select a regular file") }
            let temporary = ".porthole-\(UUID().uuidString)"
            let descriptor = openat(
                parent,
                temporary,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                0o600,
            )
            guard descriptor >= 0 else { throw failure() }
            defer { close(descriptor); unlinkat(parent, temporary, 0) }
            try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                .write(contentsOf: data)
            guard fsync(descriptor) == 0 else { throw failure() }
            if let expected {
                guard try hash(read(parent: parent, leaf: leaf)) == expected
                else { throw PortholeError.operationConflict }
                guard renameat(parent, temporary, parent, leaf) == 0 else { throw failure() }
            } else {
                guard renameatx_np(parent, temporary, parent, leaf, UInt32(RENAME_EXCL)) == 0 else {
                    if errno == EEXIST { throw PortholeError.operationConflict }
                    throw failure()
                }
            }
            guard fsync(parent) == 0 else { throw failure() }
        }
    }

    func withParent<T>(_ body: (Int32, String?) throws -> T) throws -> T {
        var descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        defer { close(descriptor) }
        for component in components.dropLast() {
            let next = openat(
                descriptor,
                component,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC,
            )
            guard next >= 0 else { throw failure() }
            close(descriptor)
            descriptor = next
        }
        return try body(descriptor, components.last)
    }

    private func read(parent: Int32, leaf: String) throws -> Data {
        let descriptor = openat(parent, leaf, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw failure() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw failure() }
        guard info.st_mode & S_IFMT == S_IFREG
        else { throw PortholeError.invalidArguments("Select a regular file") }
        let data = try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            .read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw PortholeError.capacityExceeded }
        return data
    }

    private var linkError: PortholeError {
        .invalidArguments("Symbolic links are not available through confined file operations")
    }

    private func failure() -> any Error {
        if errno == ELOOP || errno == ENOTDIR { return linkError }
        return NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
