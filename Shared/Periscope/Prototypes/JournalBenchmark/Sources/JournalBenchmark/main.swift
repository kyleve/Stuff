import Foundation

/// A representative journal entry: what a real `LogRecord` serializes to
/// (name, level, date, scopes, tags, call site, payload) — ~350 bytes.
func makePayload(seq: Int) -> Data {
    let entry: [String: Any] = [
        "id": UUID().uuidString,
        "seq": seq,
        "date": Date().timeIntervalSinceReferenceDate,
        "event": "photo-uploaded",
        "version": 1,
        "level": ["name": "info", "severity": 200],
        "message": "Uploaded photo p\(seq) (48211 bytes) after retry",
        "scopes": [UUID().uuidString, UUID().uuidString],
        "tags": ["payment-id": "pay_\(seq)", "retry": 2],
        "function": "uploadPhoto(_:)",
        "file": "Where/PhotoUploader.swift",
        "payload": ["photoID": "p\(seq)", "byteCount": 48211],
    ]
    return try! JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
}

struct Stats {
    let label: String
    let microseconds: [Double]
    let totalSeconds: Double

    var report: String {
        let sorted = microseconds.sorted()
        func percentile(_ p: Double) -> Double {
            sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
        let throughput = Double(sorted.count) / totalSeconds
        return String(
            format: "| %@ | %.1f | %.1f | %.1f | %.1f | %.0f | %.0f |",
            label.padding(toLength: 22, withPad: " ", startingAt: 0),
            percentile(0.5),
            percentile(0.9),
            percentile(0.99),
            percentile(0.999),
            sorted.last ?? 0,
            throughput,
        )
    }
}

func bench(_ variant: Variant, records: Int, threads: Int, directory: URL) throws -> Stats {
    let url = directory.appendingPathComponent("\(variant.rawValue)-\(threads)t.journal")
    let store = try variant.make(at: url)
    let payloads = (0 ..< records).map(makePayload(seq:))
    let clock = ContinuousClock()
    let latencyLock = NSLock()
    var microseconds: [Double] = []
    microseconds.reserveCapacity(records)

    let start = clock.now
    if threads == 1 {
        for seq in 0 ..< records {
            let opStart = clock.now
            try store.append(seq: seq, payload: payloads[seq])
            let elapsed = clock.now - opStart
            microseconds.append(Double(elapsed.components.attoseconds) / 1e12)
        }
    } else {
        let perThread = records / threads
        DispatchQueue.concurrentPerform(iterations: threads) { thread in
            var local: [Double] = []
            local.reserveCapacity(perThread)
            for i in 0 ..< perThread {
                let seq = thread * perThread + i
                let opStart = clock.now
                try? store.append(seq: seq, payload: payloads[seq])
                let elapsed = clock.now - opStart
                local.append(Double(elapsed.components.attoseconds) / 1e12)
            }
            latencyLock.lock()
            microseconds.append(contentsOf: local)
            latencyLock.unlock()
        }
    }
    try store.finish()
    let total = clock.now - start
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    let label = threads == 1 ? variant.rawValue : "\(variant.rawValue) ×\(threads)"
    _ = bytes
    return Stats(
        label: label,
        microseconds: microseconds,
        totalSeconds: Double(total.components.attoseconds) / 1e18 +
            Double(total.components.seconds),
    )
}

/// Child-process mode: append `killAfter` records, then SIGKILL ourselves —
/// no teardown, no atexit, exactly what a crash does.
func runVictim(variant: Variant, url: URL, killAfter: Int) throws -> Never {
    let store = try variant.make(at: url)
    for seq in 0 ..< killAfter {
        try store.append(seq: seq, payload: makePayload(seq: seq))
    }
    raise(SIGKILL)
    fatalError("unreachable")
}

func runDurability(variant: Variant, directory: URL, killAfter: Int) throws -> String {
    let url = directory.appendingPathComponent("victim-\(variant.rawValue).journal")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    process.arguments = ["victim", variant.rawValue, url.path, String(killAfter)]
    try process.run()
    process.waitUntilExit()
    let recovered = try variant.recoveredCount(at: url)
    let verdict = recovered == killAfter
        ? "all \(killAfter)"
        : "\(recovered) of \(killAfter) (lost \(killAfter - recovered))"
    return "| \(variant.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0)) | \(verdict) |"
}

// MARK: - Entry

let arguments = CommandLine.arguments
if arguments.count >= 5, arguments[1] == "victim" {
    guard let variant = Variant(rawValue: arguments[2]), let killAfter = Int(arguments[4]) else {
        exit(2)
    }
    try runVictim(variant: variant, url: URL(fileURLWithPath: arguments[3]), killAfter: killAfter)
}

let directory = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("journal-benchmark-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }

let records = 5000
print("## Emit-path latency — \(records) records, ~350-byte JSON entries, single thread\n")
print("| variant                | p50 µs | p90 µs | p99 µs | p99.9 µs | max µs | ops/s |")
print("|------------------------|--------|--------|--------|----------|--------|-------|")
for variant in Variant.allCases {
    try print(bench(variant, records: records, threads: 1, directory: directory).report)
}

print("\n## Contended — 4 threads emitting concurrently\n")
print("| variant                | p50 µs | p90 µs | p99 µs | p99.9 µs | max µs | ops/s |")
print("|------------------------|--------|--------|--------|----------|--------|-------|")
for variant in Variant.allCases {
    try print(bench(variant, records: records, threads: 4, directory: directory).report)
}

print("\n## Durability — child process SIGKILLs itself mid-stream (no teardown)\n")
print("| variant                | recovered |")
print("|------------------------|-----------|")
for variant in Variant.allCases {
    try print(runDurability(variant: variant, directory: directory, killAfter: 1050))
}
