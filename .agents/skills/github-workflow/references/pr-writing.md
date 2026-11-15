# PR descriptions

### Writing the PR body

Squash merges use the title/body as the commit message. Describe the final result, triggering problem, and decisions the diff cannot explain.
Preserve human edits.
Prefer `type(scope): imperative description` using [BACKLOG.md](../../../../BACKLOG.md) conventions; prose titles suit cross-cutting work.

#### Pick a tier

Use the [template](../../../../.github/PULL_REQUEST_TEMPLATE.md) selectively.
Small changes usually need Summary and Testing. Add Why, Design decisions, or Review focus when they answer a real review question.
Stack slices also identify position, parent PR, and whether the slice is groundwork or activates behavior.

For changed APIs/architecture, name important contracts, ownership, removals/replacements, and affected callers.
Use a short real example or reading route when needed; omit symbol inventories.
Persistence/wire changes explain old-data and parallel-install compatibility, losses, and upgrade order.
Call out breaking changes and dependent rollout steps.
Backlog changes include Linear links and remaining work.

Testing records exact commands, executed counts, and behavior covered. Label source-inspection conclusions, skipped checks, and runtime/device gaps.

#### Explain visible changes

For new screens or meaningful UI changes, include a representative set of reviewed screenshots/snapshots, usually one to three.

- Use synthetic/demo data and the reviewed revision. Follow [building-ui](../../building-ui/SKILL.md) and [running-tests](../../running-tests/SKILL.md).
- Before/after comparisons match device, appearance, data, and framing.
- Caption behavior, fixture/live capture, revision, and relevant settings; include alt text and a full-resolution link.
- Use persistent GitHub attachments or revision-pinned image URLs, including LFS images. Avoid local paths, expiring artifacts, and copies committed solely for the PR.
- Open the published PR to verify rendering/links; replace stale images after UI changes.
- Images do not prove interaction, motion, or VoiceOver behavior. Report unavailable visual evidence and remaining limits.

#### Explain complex flows with diagrams

Use Mermaid when it clarifies ownership, data flow, or lifecycle.
Name real components and relevant failure/cancellation paths; distinguish durable/in-memory state and async/atomic operations.
State omissions and avoid stronger guarantees than the implementation.
Verify syntax/rendering when available; otherwise report that limit.
