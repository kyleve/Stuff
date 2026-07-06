import ForemanCore
import Foundation
import Testing

struct WorkerOptionsTests {
    private let repoURL = URL(fileURLWithPath: "/Users/dev/Development/Thing")

    @Test func standardOptionsRenderTheMinimalArgv() {
        let arguments = WorkerOptions.standard.arguments(workerDirectory: repoURL)

        #expect(arguments == ["worker", "--worker-dir", "/Users/dev/Development/Thing", "start"])
    }

    @Test func allOptionsRenderTheirFlags() {
        let options = WorkerOptions(
            displayName: "thing-worker",
            assignment: .pool(name: "builds"),
            labels: [
                WorkerOptions.Label(key: "team", value: "ios"),
                WorkerOptions.Label(key: "gpu", value: "none"),
            ],
            idleReleaseTimeoutSeconds: 300,
            verbose: true,
        )

        let arguments = options.arguments(workerDirectory: repoURL)

        #expect(arguments == [
            "worker",
            "--worker-dir",
            "/Users/dev/Development/Thing",
            "--name",
            "thing-worker",
            "--pool",
            "--pool-name",
            "builds",
            "--label",
            "team=ios",
            "--label",
            "gpu=none",
            "--idle-release-timeout",
            "300",
            "start",
            "--verbose",
        ])
    }

    @Test func emptyPoolNameDefersToTheCLIDefault() {
        var options = WorkerOptions.standard
        options.assignment = .pool(name: "")

        let arguments = options.arguments(workerDirectory: repoURL)

        #expect(arguments.contains("--pool"))
        #expect(!arguments.contains("--pool-name"))
    }

    @Test func zeroIdleTimeoutMatchesTheCLIZeroDefaultAndIsOmitted() {
        var options = WorkerOptions.standard
        options.idleReleaseTimeoutSeconds = 0

        let arguments = options.arguments(workerDirectory: repoURL)

        #expect(!arguments.contains("--idle-release-timeout"))
    }

    @Test func codableRoundTripPreservesEveryField() throws {
        let options = WorkerOptions(
            displayName: "roundtrip",
            assignment: .pool(name: "default"),
            labels: [WorkerOptions.Label(key: "k", value: "v")],
            idleReleaseTimeoutSeconds: 42,
            verbose: true,
        )

        let decoded = try JSONDecoder().decode(
            WorkerOptions.self,
            from: JSONEncoder().encode(options),
        )

        #expect(decoded == options)
    }
}
