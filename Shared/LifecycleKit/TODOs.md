# LifecycleKit todos

The item format and the placement rule live in the root
[`TODOs.md`](../../TODOs.md); raw notes go in [`INBOX.md`](../../INBOX.md), not
here.

# Open issues

## P0s (Must do)
- fix [needs-design]: A cancel during the **final** step's `minVisible` hold is never observed, so a superseded drive still sets `phase = .ready`. `runStep` returns `.completed` unconditionally after `presentation.hold()` (`LifecycleRunner.swift:284`), and `runSteps`' cancellation check sits at the *top* of the loop (`:223`, `:251`) — so for the last step there is no next iteration to catch it, and `drive` (`:198`) reaches the terminal phase on a drive that was torn down mid-hold. Check `Task.isCancelled` after the hold, and gate the terminal phase on an active-drive token. (audit 2026-07-26)
	- test [quick-win]: Supersede a drive *during* `minVisible` — teardown or `enterForeground()` while the hold is active. `LifecycleRunnerTests.swift:430` covers the hold itself, but nothing interrupts one. (audit 2026-07-26)

## P2s (Nice to have)
- test [quick-win]: Replace the fixed 50 ms negative-assertion window (`LifecycleRunnerTests.swift:174`) with bounded polling, and add a test that duplicate step IDs trap. (audit 2026-07-26)
- fix [quick-win]: The `LifecycleContainer` `#Preview` hardcodes a literal that auto-extracts into `Sources/Resources/Localizable.xcstrings` as the value-less `App content` entry. Removing the entry for good means removing the literal. Same shape as the three Where-side literals filed in [`Where/TODOs.md`](../../Where/TODOs.md). (agent)

# Completed issues
