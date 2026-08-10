import Foundation

public struct SnapshotTimingRecord: Decodable, Equatable, Sendable {
    public let id: String
    public let total: Double
    public let phases: [String: Double]
    public let settlePasses: Int
    public let sizing: String?
    public let measurementReadiness: String?
    public let captureSettle: String?
}

public struct SnapshotDiffRecord: Decodable, Equatable, Sendable {
    public let outcome: String
    public let maxChannelDelta: Int?
    public let differingPixels: Int?
    public let differingFraction: Double?
    public let region: [Int]?
    public let reference: String?
    public let detail: String?
}

public struct SnapshotLogReport: Equatable, Sendable {
    public let timings: [SnapshotTimingRecord]
    public let differences: [SnapshotDiffRecord]

    public init(logs: [Data]) throws {
        let decoder = JSONDecoder()
        timings = try logs.flatMap { data in
            try Self.payloads(prefix: "SNAPSHOT_TIMING ", in: data).map {
                try decoder.decode(SnapshotTimingRecord.self, from: $0)
            }
        }
        differences = try logs.flatMap { data in
            try Self.payloads(prefix: "SNAPSHOT_DIFF ", in: data).map {
                try decoder.decode(SnapshotDiffRecord.self, from: $0)
            }
        }
    }

    public func timingText() -> String {
        guard timings.isEmpty == false else {
            return "  (no timing lines — was this a snapshot scheme?)\n"
        }
        let grand = timings.reduce(0) { $0 + $1.total }
        var phaseTotals: [String: Double] = [:]
        for row in timings {
            for (phase, seconds) in row.phases {
                phaseTotals[phase, default: 0] += seconds
            }
        }
        var output = String(
            format: "  %d captures, %.1fs total, %.3fs per image\n\n",
            timings.count,
            grand,
            grand / Double(timings.count),
        )
        output += "  \(padded("phase", width: 20))     total   share      mean\n"
        for (phase, seconds) in phaseTotals.sorted(by: { $0.value > $1.value }) {
            let share = grand > 0 ? 100 * seconds / grand : 0
            output += "  \(padded(phase, width: 20)) "
            output += String(
                format: "%8.2fs %6.1f%% %8.3fs\n",
                seconds,
                share,
                seconds / Double(timings.count),
            )
        }
        let passes = timings.map(\.settlePasses)
        let mean = Double(passes.reduce(0, +)) / Double(passes.count)
        output += "\n  settle passes: min \(passes.min() ?? 0), max \(passes.max() ?? 0), "
        output += String(format: "mean %.1f\n", mean)
        output += "\n  slowest captures:\n"
        for row in timings.sorted(by: { $0.total > $1.total }).prefix(8) {
            output += String(format: "    %6.3fs  %@\n", row.total, row.id)
        }
        return output
    }

    public func differenceText(isRecording: Bool) -> String {
        let rows = isRecording
            ? differences.filter { $0.outcome != "referenceMissing" }
            : differences
        guard rows.isEmpty == false else {
            return "  Every capture matched its reference byte for byte.\n"
        }
        let differs = rows.filter { $0.outcome == "differs" }
        var output = "  \(rows.count) capture(s) did not match byte for byte.\n\n"
        if differs.isEmpty == false {
            output += "  maxDelta   pixels  of image  region (x,y,w,h)  reference\n"
            for row in differs.sorted(by: {
                ($0.maxChannelDelta ?? 0) > ($1.maxChannelDelta ?? 0)
            }) {
                let region = row.region?.map(String.init).joined(separator: ",") ?? "?"
                let reference = row.reference?
                    .components(separatedBy: "__Snapshots__/").last ?? "?"
                output += String(
                    format: "  %8d %8d %8.3f%%  (%@)  %@\n",
                    row.maxChannelDelta ?? 0,
                    row.differingPixels ?? 0,
                    100 * (row.differingFraction ?? 0),
                    region,
                    reference,
                )
            }
            output += "\n  A single-digit max delta is sub-visible drift; a large one is a real\n"
            output += "  change however few pixels it touches.\n"
        }
        for row in rows where row.outcome != "differs" {
            output += "  \(row.outcome): \(row.reference ?? row.detail ?? "")\n"
        }
        return output
    }

    public func profileTimingText() -> String {
        guard timings.isEmpty == false else {
            return "  (no timing lines found)\n"
        }
        let grand = timings.reduce(0) { $0 + $1.total }
        var phaseTotals: [String: Double] = [:]
        for row in timings {
            for (phase, seconds) in row.phases {
                phaseTotals[phase, default: 0] += seconds
            }
        }
        var output = String(
            format: "  %d captures, %.1fs total, %.3fs per image\n\n",
            timings.count,
            grand,
            grand / Double(timings.count),
        )
        output += "  \(padded("phase", width: 20))     total   share      mean\n"
        for (phase, seconds) in phaseTotals.sorted(by: { $0.value > $1.value }) {
            let share = grand > 0 ? 100 * seconds / grand : 0
            output += "  \(padded(phase, width: 20)) "
            output += String(
                format: "%8.2fs %6.1f%% %8.3fs\n",
                seconds,
                share,
                seconds / Double(timings.count),
            )
        }
        output += countText(title: "sizing", values: timings.map { $0.sizing ?? "unknown" })
        output += countText(
            title: "measurement readiness",
            values: timings.map { $0.measurementReadiness ?? "unknown" },
        )
        output += countText(
            title: "capture settle",
            values: timings.map { $0.captureSettle ?? "unknown" },
        )
        output += "\n  intrinsic measurement by readiness:\n"
        let readinessValues = Set(timings.map { $0.measurementReadiness ?? "unknown" }).sorted()
        for readiness in readinessValues {
            let selected = timings.filter { ($0.measurementReadiness ?? "unknown") == readiness }
            let seconds = selected.reduce(0) { result, row in
                result + row.phases["intrinsicMeasure", default: 0]
            }
            output += String(
                format: "    %8.2fs  %@ (%d captures)\n",
                seconds,
                readiness,
                selected.count,
            )
        }
        let passes = timings.map(\.settlePasses)
        let mean = Double(passes.reduce(0, +)) / Double(passes.count)
        output += "\n  settle passes: min \(passes.min() ?? 0), max \(passes.max() ?? 0), "
        output += String(format: "mean %.1f\n", mean)
        output += "\n  slowest captures:\n"
        for row in timings.sorted(by: { $0.total > $1.total }).prefix(8) {
            output += String(format: "    %6.3fs  %@\n", row.total, row.id)
        }
        return output
    }

    private static func payloads(prefix: String, in data: Data) -> [Data] {
        String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                guard let range = line.range(of: prefix) else { return nil }
                return Data(line[range.upperBound...].utf8)
            }
    }

    private func padded(_ value: String, width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    private func countText(title: String, values: [String]) -> String {
        var counts: [String: Int] = [:]
        for value in values {
            counts[value, default: 0] += 1
        }
        var output = "\n  \(title):\n"
        for (value, count) in counts.sorted(by: {
            if $0.value == $1.value { return $0.key < $1.key }
            return $0.value > $1.value
        }) {
            output += String(format: "    %4d  %@\n", count, value)
        }
        return output
    }
}
