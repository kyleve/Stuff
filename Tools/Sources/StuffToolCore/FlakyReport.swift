import Foundation

public struct FlakySuiteStat: Codable, Equatable, Sendable {
    public let bundle: String
    public let name: String
    public let failures: Int
    public let seen: Int

    public init(bundle: String, name: String, failures: Int, seen: Int) {
        self.bundle = bundle
        self.name = name
        self.failures = failures
        self.seen = seen
    }

    private enum CodingKeys: String, CodingKey {
        case bundle
        case name
        case failures = "fails"
        case seen
    }
}

public struct FlakyTightCounts: Equatable, Sendable {
    public let failures: Int
    public let total: Int

    public init(failures: Int, total: Int) {
        self.failures = failures
        self.total = total
    }
}

public struct FlakySuiteAnalysis: Equatable, Sendable {
    public let stats: [String: FlakySuiteStat]

    public init(stats: [String: FlakySuiteStat]) {
        self.stats = stats
    }

    public init(catalogs: [XCResultTestCatalog]) {
        var stats: [String: FlakySuiteStat] = [:]
        for testCase in catalogs.flatMap(\.testCases) {
            let current = stats[testCase.identifier] ?? FlakySuiteStat(
                bundle: testCase.bundle,
                name: testCase.name,
                failures: 0,
                seen: 0,
            )
            stats[testCase.identifier] = FlakySuiteStat(
                bundle: current.bundle,
                name: current.name,
                failures: current.failures + (testCase.result.lowercased() == "failed" ? 1 : 0),
                seen: current.seen + 1,
            )
        }
        self.stats = stats
    }

    public var suspects: [String] {
        stats.compactMap { identifier, stat in
            stat.failures > 0 ? identifier : nil
        }.sorted()
    }

    public func encodedCounts() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(stats)
    }

    public static func tightCounts(
        catalog: XCResultTestCatalog?,
        summary: XCResultSummary?,
    ) -> FlakyTightCounts {
        let results = catalog?.testCases.map { $0.result.lowercased() } ?? []
        if results.count >= 2 {
            return FlakyTightCounts(
                failures: results.count(where: { $0 == "failed" }),
                total: results.count,
            )
        }

        if let summary {
            let failures = summary.failedTests ?? 0
            let passed = summary.passedTests ?? 0
            if failures + passed > 0 {
                return FlakyTightCounts(failures: failures, total: failures + passed)
            }
        }

        return FlakyTightCounts(
            failures: results.count(where: { $0 == "failed" }),
            total: results.count,
        )
    }
}

public struct FlakyReportRow: Equatable, Sendable {
    public let identifier: String
    public let bundle: String
    public let name: String
    public let suiteFailures: Int
    public let suiteRuns: Int
    public let tightFailures: Int
    public let tightTotal: Int
    public let flakeRate: Double

    public init(
        identifier: String,
        bundle: String,
        name: String,
        suiteFailures: Int,
        suiteRuns: Int,
        tightFailures: Int,
        tightTotal: Int,
        flakeRate: Double,
    ) {
        self.identifier = identifier
        self.bundle = bundle
        self.name = name
        self.suiteFailures = suiteFailures
        self.suiteRuns = suiteRuns
        self.tightFailures = tightFailures
        self.tightTotal = tightTotal
        self.flakeRate = flakeRate
    }

    public var tightCell: String {
        tightTotal > 0 ? "\(tightFailures)/\(tightTotal)" : "n/a"
    }
}

public struct FlakyReportMetadata: Equatable, Sendable {
    public let date: Date
    public let suiteRuns: Int
    public let iterations: Int
    public let relaunch: String
    public let device: String
    public let os: String
    public let top: Int?

    public init(
        date: Date,
        suiteRuns: Int,
        iterations: Int,
        relaunch: String,
        device: String,
        os: String,
        top: Int?,
    ) {
        self.date = date
        self.suiteRuns = suiteRuns
        self.iterations = iterations
        self.relaunch = relaunch
        self.device = device
        self.os = os
        self.top = top
    }
}

public struct FlakyReport: Equatable, Sendable {
    public let rows: [FlakyReportRow]

    public init(
        suite: FlakySuiteAnalysis,
        tightCounts: [String: FlakyTightCounts],
        suiteRuns: Int,
    ) {
        rows = suite.stats.compactMap { identifier, stat in
            let tight = tightCounts[identifier] ?? FlakyTightCounts(failures: 0, total: 0)
            let combinedFailures = stat.failures + tight.failures
            let combinedPasses = (stat.seen - stat.failures) + (tight.total - tight.failures)
            guard combinedFailures > 0, combinedPasses > 0 else { return nil }

            var rates = [Double(stat.failures) / Double(suiteRuns)]
            if tight.total > 0 {
                rates.append(Double(tight.failures) / Double(tight.total))
            }
            return FlakyReportRow(
                identifier: identifier,
                bundle: stat.bundle,
                name: stat.name,
                suiteFailures: stat.failures,
                suiteRuns: suiteRuns,
                tightFailures: tight.failures,
                tightTotal: tight.total,
                flakeRate: rates.reduce(0, +) / Double(rates.count),
            )
        }.sorted {
            if $0.flakeRate != $1.flakeRate { return $0.flakeRate > $1.flakeRate }
            if $0.suiteFailures != $1.suiteFailures {
                return $0.suiteFailures > $1.suiteFailures
            }
            return $0.identifier < $1.identifier
        }
    }

    public func consoleText(top: Int?) -> String {
        let shown = shownRows(top: top)
        guard shown.isEmpty == false else { return "No flaky tests detected.\n" }

        var output = "\(rows.count) flaky test(s) detected"
        if let top, rows.count > top {
            output += " (showing top \(top))"
        }
        output += ":\n\n"
        for row in shown {
            output += String(
                format: "  %5.1f%%  suite %d/%d  tight %@  %@\n",
                row.flakeRate * 100,
                row.suiteFailures,
                row.suiteRuns,
                row.tightCell,
                row.identifier,
            )
        }
        return output
    }

    public func markdown(_ metadata: FlakyReportMetadata) -> String {
        let shown = shownRows(top: metadata.top)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines = [
            "# Flaky tests",
            "",
            "<!-- Generated by ./flaky — do not hand-edit. Re-run ./flaky to refresh. -->",
            "",
            "_Last run: \(formatter.string(from: metadata.date)) · suite runs: " +
                "\(metadata.suiteRuns) · tight-loop iterations: \(metadata.iterations) · " +
                "relaunch: \(metadata.relaunch) · destination: \(metadata.device) / iOS " +
                "\(metadata.os)._",
            "",
            "A test is listed here only when it produced **both** passes and failures across the",
            "suite runs and the per-test tight loop — i.e. it is genuinely non-deterministic.",
            "Tests that always pass, or that always fail (broken, not flaky), are omitted.",
            "The flake rate averages the suite failure rate and the tight-loop failure rate.",
            "",
            "## Detected flaky tests",
            "",
        ]
        if shown.isEmpty {
            lines.append("None detected in the latest run.")
        } else {
            lines += [
                "| Test | Bundle | Suite fails | Tight-loop fails | Flake rate |",
                "|------|--------|-------------|------------------|------------|",
            ]
            for row in shown {
                lines.append(
                    "| `\(row.identifier)` | \(row.bundle) | " +
                        "\(row.suiteFailures)/\(row.suiteRuns) | \(row.tightCell) | " +
                        String(format: "%.0f%% |", row.flakeRate * 100),
                )
            }
            if let top = metadata.top, rows.count > top {
                lines += [
                    "",
                    "_(+\(rows.count - top) more not shown; raise `--top` to list them.)_",
                ]
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func shownRows(top: Int?) -> ArraySlice<FlakyReportRow> {
        rows.prefix(top ?? rows.count)
    }
}
