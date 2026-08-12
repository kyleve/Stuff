import Darwin
import Foundation
import Subprocess

/// A public-command fixture whose first tool invocation owns an uncooperative grandchild.
struct PublicShimProcessFixture {
    let repository: URL
    let temporaryDirectory: URL
    let stuffPIDFile: URL
    let childPIDFile: URL
    let grandchildPIDFile: URL
    let childSignalFile: URL
    let grandchildSignalFile: URL

    init(repository: URL = testRepositoryRoot) throws {
        self.repository = repository
        temporaryDirectory = try makeTemporaryDirectory()
        stuffPIDFile = temporaryDirectory.appending(path: "stuff.pid")
        childPIDFile = temporaryDirectory.appending(path: "child.pid")
        grandchildPIDFile = temporaryDirectory.appending(path: "grandchild.pid")
        childSignalFile = temporaryDirectory.appending(path: "child.signal")
        grandchildSignalFile = temporaryDirectory.appending(path: "grandchild.signal")

        let binaries = temporaryDirectory.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: false)
        try writeExecutable(Self.xcrunScript, to: binaries.appending(path: "xcrun"))
        try writeExecutable(Self.miseScript, to: binaries.appending(path: "mise"))
    }

    var whereInstall: URL {
        repository.appending(path: "Where/install")
    }

    func environment(writeOutput: Bool = false) throws -> [String: String] {
        guard FileManager.default.isExecutableFile(atPath: prebuiltStuffExecutable.path) else {
            throw ProcessTestSupportFailure.missingStuffExecutable(prebuiltStuffExecutable)
        }
        var environment = ProcessInfo.processInfo.environment
        let binaries = temporaryDirectory.appending(path: "bin", directoryHint: .isDirectory)
        environment["PATH"] = binaries.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["STUFF_TEST_STUFF_PID_FILE"] = stuffPIDFile.path
        environment["STUFF_TEST_CHILD_PID_FILE"] = childPIDFile.path
        environment["STUFF_TEST_GRANDCHILD_PID_FILE"] = grandchildPIDFile.path
        environment["STUFF_TEST_CHILD_SIGNAL_FILE"] = childSignalFile.path
        environment["STUFF_TEST_GRANDCHILD_SIGNAL_FILE"] = grandchildSignalFile.path
        environment["STUFF_TEST_STUFF_EXECUTABLE"] = prebuiltStuffExecutable.path
        if writeOutput {
            environment["STUFF_TEST_WRITE_OUTPUT"] = "1"
        } else {
            environment.removeValue(forKey: "STUFF_TEST_WRITE_OUTPUT")
        }
        return environment
    }

    func subprocessEnvironment(writeOutput: Bool = false) throws -> Environment {
        let environment = try environment(writeOutput: writeOutput)
        let pairs = try environment.map { key, value -> (Environment.Key, String) in
            guard let key = Environment.Key(rawValue: key) else {
                throw ProcessTestSupportFailure.invalidEnvironmentKey(key)
            }
            return (key, value)
        }
        return .custom(Dictionary(uniqueKeysWithValues: pairs))
    }

    func cleanUp() {
        for file in [grandchildPIDFile, childPIDFile, stuffPIDFile] {
            if let processID = try? processID(in: file) {
                _ = Darwin.kill(processID, SIGKILL)
            }
        }
        removeTemporaryDirectory(temporaryDirectory)
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path,
        )
    }

    private static let xcrunScript = """
    #!/bin/sh
    set -eu

    if [ "${1:-}" = swift ] && [ -n "${STUFF_TEST_STUFF_EXECUTABLE:-}" ]; then
        printf '%s\\n' "$$" > "$STUFF_TEST_STUFF_PID_FILE"
        while [ "$#" -gt 0 ] && [ "$1" != stuff ]; do
            shift
        done
        [ "$#" -gt 0 ] || exit 64
        shift
        exec "$STUFF_TEST_STUFF_EXECUTABLE" "$@"
    fi

    exec /usr/bin/xcrun "$@"
    """

    private static let miseScript = """
    #!/bin/sh

    record_signal() {
        [ -e "$STUFF_TEST_CHILD_SIGNAL_FILE" ] || printf '%s\\n' "$1" > "$STUFF_TEST_CHILD_SIGNAL_FILE"
    }
    trap 'record_signal INT' INT
    trap 'record_signal TERM' TERM
    trap 'record_signal PIPE' PIPE
    printf '%s\\n' "$$" > "$STUFF_TEST_CHILD_PID_FILE"

    /bin/sh -c '
        record_signal() {
            [ -e "$STUFF_TEST_GRANDCHILD_SIGNAL_FILE" ] || printf "%s\\n" "$1" > "$STUFF_TEST_GRANDCHILD_SIGNAL_FILE"
        }
        trap "record_signal INT" INT
        trap "record_signal TERM" TERM
        trap "record_signal PIPE" PIPE
        printf "%s\\n" "$$" > "$STUFF_TEST_GRANDCHILD_PID_FILE"
        while :; do
            /bin/sleep 1
        done
    ' </dev/null >/dev/null 2>&1 &
    grandchild=$!

    if [ "${STUFF_TEST_WRITE_OUTPUT:-}" = 1 ]; then
        while [ ! -s "$STUFF_TEST_GRANDCHILD_PID_FILE" ]; do
            :
        done
        while kill -0 "$grandchild" 2>/dev/null; do
            printf "fixture output\\n" >&2 || :
        done
    else
        while kill -0 "$grandchild" 2>/dev/null; do
            wait "$grandchild" || :
        done
    fi
    """
}

/// A pipe filled before launch so a child terminal write cannot make progress.
struct FullOutputPipe {
    let readDescriptor: Int32
    let writeDescriptor: Int32

    init() throws {
        var descriptors = [Int32](repeating: -1, count: 2)
        let pipeResult = descriptors.withUnsafeMutableBufferPointer { buffer in
            Darwin.pipe(buffer.baseAddress!)
        }
        guard pipeResult == 0 else {
            throw ProcessTestSupportFailure.posix("pipe", errno)
        }
        readDescriptor = descriptors[0]
        writeDescriptor = descriptors[1]
        do {
            try Self.fill(writeDescriptor)
        } catch {
            close()
            throw error
        }
    }

    func close() {
        _ = Darwin.close(readDescriptor)
        _ = Darwin.close(writeDescriptor)
    }

    private static func fill(_ descriptor: Int32) throws {
        let originalFlags = Darwin.fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              Darwin.fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
        else {
            throw ProcessTestSupportFailure.posix("fcntl", errno)
        }
        defer { _ = Darwin.fcntl(descriptor, F_SETFL, originalFlags) }

        let bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = bytes.withUnsafeBytes { buffer in
                Darwin.write(descriptor, buffer.baseAddress, buffer.count)
            }
            if count >= 0 {
                continue
            }
            guard errno == EAGAIN else {
                throw ProcessTestSupportFailure.posix("write", errno)
            }
            return
        }
    }
}

enum ProcessTestSupportFailure: Error, CustomStringConvertible {
    case invalidEnvironmentKey(String)
    case invalidProcessID(URL)
    case missingStuffExecutable(URL)
    case posix(String, Int32)
    case processDidNotAppear(URL)
    case processDidNotExit(pid_t)

    var description: String {
        switch self {
            case let .invalidEnvironmentKey(key):
                "invalid environment key '\(key)'"
            case let .invalidProcessID(url):
                "invalid process identifier in \(url.path)"
            case let .missingStuffExecutable(url):
                "prebuilt stuff executable is missing at \(url.path)"
            case let .posix(function, errorNumber):
                "\(function) failed with errno \(errorNumber)"
            case let .processDidNotAppear(url):
                "process identifier did not appear at \(url.path)"
            case let .processDidNotExit(processID):
                "process \(processID) did not exit"
        }
    }
}

func waitForProcessID(
    in file: URL,
    timeout: Duration = .seconds(20),
) async throws -> pid_t {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    repeat {
        if FileManager.default.fileExists(atPath: file.path) {
            return try processID(in: file)
        }
        try await Task.sleep(for: .milliseconds(10))
    } while clock.now < deadline
    throw ProcessTestSupportFailure.processDidNotAppear(file)
}

func waitForProcessExit(
    _ processID: pid_t,
    timeout: Duration = .seconds(10),
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    repeat {
        guard isProcessAlive(processID) else { return }
        try await Task.sleep(for: .milliseconds(10))
    } while clock.now < deadline
    throw ProcessTestSupportFailure.processDidNotExit(processID)
}

func waitForFileContents(
    at file: URL,
    timeout: Duration = .seconds(10),
) async throws -> String {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    repeat {
        if let value = try? String(contentsOf: file, encoding: .utf8), value.isEmpty == false {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try await Task.sleep(for: .milliseconds(10))
    } while clock.now < deadline
    throw ProcessTestSupportFailure.processDidNotAppear(file)
}

func isProcessAlive(_ processID: pid_t) -> Bool {
    errno = 0
    return Darwin.kill(processID, 0) == 0 || errno == EPERM
}

private let testRepositoryRoot = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private let prebuiltStuffExecutable: URL = {
    var directory = Bundle.module.bundleURL
    repeat {
        let candidate = directory.appending(path: "stuff")
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        let parent = directory.deletingLastPathComponent()
        guard parent != directory else { break }
        directory = parent
    } while true
    return Bundle.module.bundleURL.appending(path: "stuff")
}()

private func processID(in file: URL) throws -> pid_t {
    let value = try String(contentsOf: file, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let processID = pid_t(value), processID > 0 else {
        throw ProcessTestSupportFailure.invalidProcessID(file)
    }
    return processID
}
