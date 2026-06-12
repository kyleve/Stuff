import LifecycleKit
import SwiftUI
import Testing
import WhereTesting

private struct ProbeError: LocalizedError {
    var errorDescription: String? {
        "probe failure"
    }
}

/// Records whether each branch of `LaunchContainer` actually built its view,
/// detected by a side effect in `ProbeView.body` (which only runs when the
/// container chooses that branch and the host lays it out).
@MainActor
private final class RenderFlags {
    var splash = false
    var content = false
    var presentation = false
}

private struct ProbeView: View {
    let mark: () -> Void

    var body: some View {
        mark()
        return Color.clear.frame(width: 1, height: 1)
    }
}

@MainActor
private func makeContainer(
    _ launcher: Launcher,
    flags: RenderFlags,
) -> some View {
    LaunchContainer(launcher, splash: { ProbeView { flags.splash = true } }) {
        ProbeView { flags.content = true }
    }
}

@MainActor
struct LaunchContainerTests {
    @Test func readyShowsContent() async throws {
        let flags = RenderFlags()
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {})
        await launcher.run()
        #expect(launcher.phase.isReady)

        try show(UIHostingController(rootView: makeContainer(launcher, flags: flags))) { _ in
            try waitFor { flags.content }
        }
        #expect(flags.content)
        #expect(!flags.splash)
    }

    @Test func launchingShowsSplash() throws {
        let flags = RenderFlags()
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("a") { _ in }
        })
        // Not run yet, so the launcher is still in .launching.

        try show(UIHostingController(rootView: makeContainer(launcher, flags: flags))) { _ in
            try waitFor { flags.splash }
        }
        #expect(flags.splash)
        #expect(!flags.content)
    }

    @Test func backgroundLaunchShowsNothing() async throws {
        let flags = RenderFlags()
        let launcher = Launcher(reason: .background(.location), sequence: LaunchSequence {})
        await launcher.run()
        #expect(launcher.phase.isReady)

        try show(UIHostingController(rootView: makeContainer(launcher, flags: flags))) { _ in
            waitForOneRunloop()
            waitForOneRunloop()
            waitForOneRunloop()
            // Even at .ready, a background launch must not build the app UI.
            #expect(!flags.content)
            #expect(!flags.splash)
        }
    }

    @Test func runningShowsActivePresentation() async throws {
        let flags = RenderFlags()
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Interactive("gate") { _ in ProbeView { flags.presentation = true } }
        })
        let task = Task { @MainActor in await launcher.run() }
        try await waitUntil { launcher.phase.runningStepID == "gate" }

        try show(UIHostingController(rootView: makeContainer(launcher, flags: flags))) { _ in
            try waitFor { flags.presentation }
        }
        #expect(flags.presentation)
        #expect(!flags.content)

        launcher.phase.runningHandle?.complete()
        await task.value
    }

    @Test func failedShowsFailureView() async throws {
        let flags = RenderFlags()
        let launcher = Launcher(reason: .userForeground, sequence: LaunchSequence {
            Work("boom") { _ in throw ProbeError() }
        })
        await launcher.run()
        #expect(launcher.phase.failure?.stepID == "boom")

        try show(UIHostingController(rootView: makeContainer(launcher, flags: flags))) { hosted in
            waitForOneRunloop()
            waitForOneRunloop()
            #expect(hosted.view != nil)
            #expect(!flags.content)
            #expect(!flags.splash)
        }
    }
}
