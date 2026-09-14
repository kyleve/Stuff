# PortholeJavaScript

This module runs a bounded JavaScript console inside the app. It uses the
vendored QuickJS-NG interpreter through CQuickJS. It needs no JIT or subprocess.

Create `PortholeJavaScriptSession` at the debugger composition root. Supply
explicit limits, an event handler, and the shared native dispatcher.

```swift
let session = PortholeJavaScriptSession(
    limits: .interactive,
    nativeCall: { name, arguments in
        try await dispatcher(name, arguments)
    },
    events: { event in journal.record(event) }
)
let result = try await session.execute(
    source: "await porthole.call('discover', {})"
)
```

Scripts support top-level `await`. The last expression becomes the result.
Each command has a fresh VM. Use native context and object handles to carry
references between commands. Native operations return promises through
`porthole.call(name, arguments)`.

Values use JSON shapes. Native integers outside JavaScript's safe integer range
become `bigint`. Use `123n` syntax for exact large integers. The bridge rejects
BigInt values below Int64.min or above UInt64.max, non-finite numbers, cycles, and unsupported values.
Unsafe integer Number arguments also fail before native execution; use a BigInt literal instead.
An absent result becomes `null`.

All engine work stays on a private serial queue. Native tasks pass immutable
values through a locked mailbox. They never access QuickJS objects. Events arrive
on the engine queue and exclude credentials. The handler must return promptly.

Limits cover heap, stack, source bytes, value bytes, native calls, and elapsed
time. Time continues while a promise waits. `cancel()` and Swift task cancellation
interrupt the engine and cancel native tasks. Native operations must cooperate;
cancellation cannot undo a completed mutation. Unawaited native tasks are cancelled
when the command finishes.

The VM has no filesystem, process, network, or module loader. The injected
dispatcher owns authorization, validation, approval, and audit records.

Run `swift test --package-path Shared/Porthole --filter PortholeJavaScriptTests` from the repository root.
