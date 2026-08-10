import Foundation

public struct BuildPhaseTiming: Equatable, Sendable {
    public let name: String
    public let tasks: Int
    public let seconds: Double

    public init(name: String, tasks: Int, seconds: Double) {
        self.name = name
        self.tasks = tasks
        self.seconds = seconds
    }
}

public struct TypeCheckTiming: Equatable, Sendable {
    public let location: String
    public let milliseconds: Int

    public init(location: String, milliseconds: Int) {
        self.location = location
        self.milliseconds = milliseconds
    }
}

/// Best-effort parsing for Xcode's human-readable build timing summary.
public struct BuildTimingReport: Equatable, Sendable {
    public let phases: [BuildPhaseTiming]
    public let typeChecks: [TypeCheckTiming]

    public init(log: Data) {
        var phases: [BuildPhaseTiming] = []
        var typeChecks: [TypeCheckTiming] = []
        for line in String(decoding: log, as: UTF8.self).split(separator: "\n") {
            let text = String(line)
            if let phase = Self.phase(in: text) {
                phases.append(phase)
            }
            if let typeCheck = Self.typeCheck(in: text) {
                typeChecks.append(typeCheck)
            }
        }
        self.phases = phases
        self.typeChecks = typeChecks
    }

    public func text(typeCheckThreshold: Int) -> String {
        var output = ""
        if phases.isEmpty {
            output += "  (no build-timing summary found — was this a no-op incremental build?)\n"
        } else {
            let total = phases.reduce(0) { $0 + $1.seconds }
            output += "Build phases (summed task-time across cores; wall is lower thanks to\n"
            output += "parallelism — use the shares, not the absolute seconds):\n"
            for phase in phases.sorted(by: { $0.seconds > $1.seconds }) {
                let share = total > 0 ? 100 * phase.seconds / total : 0
                output += String(
                    format: "  %8.2fs  %4.0f%%  %@ (%d)\n",
                    phase.seconds,
                    share,
                    phase.name,
                    phase.tasks,
                )
            }
        }
        output += "\n"
        if typeChecks.isEmpty {
            output += "Slow type-check sites (limit \(typeCheckThreshold)ms): none — no expression or\n"
            output += "function body exceeded the threshold.\n"
        } else {
            output += "Slow type-check sites (limit \(typeCheckThreshold)ms):\n"
            for timing in typeChecks.sorted(by: { $0.milliseconds > $1.milliseconds }) {
                output += String(
                    format: "  %6dms  %@\n",
                    timing.milliseconds,
                    timing.location,
                )
            }
        }
        return output
    }

    private static func phase(in line: String) -> BuildPhaseTiming? {
        guard line.hasSuffix(" seconds"),
              let separator = line.range(of: " | ", options: .backwards)
        else {
            return nil
        }
        let secondsText = line[separator.upperBound...].dropLast(" seconds".count)
        guard let seconds = Double(secondsText) else { return nil }
        let description = line[..<separator.lowerBound]
        guard description.hasSuffix(")"),
              let opening = description.range(of: " (", options: .backwards)
        else {
            return nil
        }
        let taskText = description[opening.upperBound...].dropLast()
            .replacingOccurrences(of: " tasks", with: "")
            .replacingOccurrences(of: " task", with: "")
        guard let tasks = Int(taskText) else { return nil }
        return BuildPhaseTiming(
            name: String(description[..<opening.lowerBound]).trimmingCharacters(in: .whitespaces),
            tasks: tasks,
            seconds: seconds,
        )
    }

    private static func typeCheck(in line: String) -> TypeCheckTiming? {
        guard let warning = line.range(of: ": warning: ") else { return nil }
        let location = String(line[..<warning.lowerBound])
        let message = line[warning.upperBound...]
        guard let took = message.range(of: "took "),
              let suffix = message.range(
                  of: "ms to type-check",
                  range: took.upperBound ..< message.endIndex,
              ),
              let milliseconds = Int(message[took.upperBound ..< suffix.lowerBound])
        else {
            return nil
        }
        return TypeCheckTiming(
            location: shortened(location),
            milliseconds: milliseconds,
        )
    }

    private static func shortened(_ location: String) -> String {
        for marker in ["/Where/", "/Shared/"] {
            if let range = location.range(of: marker) {
                return String(location[location.index(after: range.lowerBound)...])
            }
        }
        return location
    }
}
