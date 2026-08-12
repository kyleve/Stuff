import Foundation

/// Aggregates per-case durations from one or more disjoint test-scheme catalogs.
struct TestHotSpotReport: Equatable {
    let cases: [XCResultTestCase]

    init(catalogs: [XCResultTestCatalog]) {
        cases = catalogs.flatMap(\.testCases).filter {
            $0.result.caseInsensitiveCompare("Skipped") != .orderedSame
        }
    }

    func text(top: Int, threshold: Double) -> String {
        let total = cases.reduce(0) { $0 + $1.durationInSeconds }
        var output = String(
            format: "%d tests, summed self-time %.2fs\n\n",
            cases.count,
            total,
        )
        output += "Slowest \(top) tests:\n"
        let slowest = cases.sorted {
            if $0.durationInSeconds == $1.durationInSeconds {
                return $0.identifier < $1.identifier
            }
            return $0.durationInSeconds > $1.durationInSeconds
        }.prefix(top)
        for testCase in slowest {
            let flag = testCase.durationInSeconds >= threshold ? "  <== over threshold" : ""
            output += String(
                format: "  %7.3fs  %@ / %@%@\n",
                testCase.durationInSeconds,
                testCase.bundle,
                testCase.name,
                flag,
            )
        }

        var bundles: [String: (duration: Double, count: Int)] = [:]
        for testCase in cases {
            var value = bundles[testCase.bundle, default: (0, 0)]
            value.duration += testCase.durationInSeconds
            value.count += 1
            bundles[testCase.bundle] = value
        }
        output += "\nPer-bundle self-time:\n"
        for (bundle, value) in bundles.sorted(by: {
            if $0.value.duration == $1.value.duration { return $0.key < $1.key }
            return $0.value.duration > $1.value.duration
        }) {
            output += String(
                format: "  %7.3fs  %@ (%d tests)\n",
                value.duration,
                bundle,
                value.count,
            )
        }

        let over = cases.count { $0.durationInSeconds >= threshold }
        output += "\n"
        if over > 0 {
            output += "\(over) test(s) at/over the \(threshold)s threshold (flagged above).\n"
        } else {
            output += "No tests at/over the \(threshold)s threshold.\n"
        }
        return output
    }
}
