import LifecycleKit
import SwiftUI

extension EnvironmentValues {
    /// A handle to the running `LifecycleRunner`, published by
    /// `LifecycleContainer` so nested views (a Settings "reset" button) can
    /// reach `enterForeground()`/`teardown(_:input:)` without prop-drilling.
    ///
    /// It's a `LifecycleProxy` rather than a bare runner for two reasons: an
    /// environment value must be non-generic (the runner is generic over its
    /// `Launch`), and a view that reads it can just *call* the runner — when
    /// no container is above (previews, isolated tests) the proxy is
    /// disconnected and every call asserts in debug (surfacing the missing
    /// container) and no-ops in release, instead of each call site silently
    /// `guard`ing an optional away.
    @Entry public var lifecycle = LifecycleProxy()
}

/// A debug-loud, release-quiet handle to the environment's `LifecycleRunner`.
///
/// `LifecycleContainer` publishes a *connected* proxy; the environment
/// default is *disconnected* (no runner). Calling through a disconnected
/// proxy `assertionFailure`s in debug (so a view used outside a container is
/// caught in development) and no-ops in release (so a stray reset/retry tap
/// can't crash a shipping build). Views therefore drive the runner without
/// `guard`ing — the "is there a runner?" decision lives here, once.
///
/// The wrapped runner is `@MainActor`; every forwarding entry point is
/// annotated `@MainActor` accordingly. The struct itself stays `Sendable` so
/// it can be the `@Entry` default — callers must invoke it from the main
/// actor (SwiftUI views already do).
public struct LifecycleProxy: Sendable {
    let base: (any LifecycleDriving)?

    /// A disconnected proxy (no runner): the environment default, and what
    /// previews get so reset/retry quietly do nothing.
    public init() {
        base = nil
    }

    init(_ runner: any LifecycleDriving) {
        base = runner
    }

    /// Promote a headless launch to the foreground.
    /// See `LifecycleRunner.enterForeground()`.
    @MainActor public func enterForeground(file: StaticString = #fileID, line: UInt = #line) async {
        await connected(file: file, line: line)?.enterForeground()
    }

    /// Run a typed teardown `plan` rooted at `input`, then relaunch from the
    /// top. See `LifecycleRunner.teardown(_:input:)`. The plan and input are
    /// type-checked here, at the call site, and erased only to cross the
    /// non-generic environment seam.
    @MainActor public func teardown<Input: Sendable>(
        _ plan: LaunchPlan<some Hashable & Sendable, Input, some Sendable>,
        input: Input,
        file: StaticString = #fileID,
        line: UInt = #line,
    ) async {
        await connected(file: file, line: line)?.teardownErased(nodes: plan.nodes, input: input)
    }

    /// The wrapped runner, or nil with a debug assertion pointing at the
    /// caller — so a disconnected proxy is loud in development and a silent
    /// no-op in production.
    private func connected(file: StaticString, line: UInt) -> (any LifecycleDriving)? {
        if base == nil {
            assertionFailure(
                "No LifecycleRunner in the environment — is this view inside a LifecycleContainer?",
                file: file,
                line: line,
            )
        }
        return base
    }
}
