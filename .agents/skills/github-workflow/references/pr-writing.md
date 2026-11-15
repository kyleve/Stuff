# PR descriptions

### Writing the PR body

Squash merges use the PR title as commit subject and the body as commit body. Write for a future reader of `git show`.
Describe the final behavior and motivation, including trade-offs the diff cannot explain. Preserve human edits when refreshing the title or body.
Prefer `type(scope): imperative description`, using [BACKLOG.md](../../../../BACKLOG.md) types and scopes; prose titles are fine for cross-cutting work.
For bug fixes, name the trigger and visible symptom or relevant error text so future readers can find the decision.

#### Pick a tier

Use only sections that answer a review question. Omit unused headers and placeholders.

| Change | Useful sections and detail |
| --- | --- |
| Small fix | Summary and Testing; Why or Review focus for subtle behavior. |
| Feature or behavior change | Summary, Why, Review focus, Testing; distinguish user-facing and internal changes when mixed. |
| Architecture or multi-module work | Problem, Changes, Design decisions, Architecture or Product behavior, Review focus, Testing. Explain key types, invariants, and ownership. |
| Refactor or migration | What moved or disappeared, changed ownership/APIs, design decisions, compiler guarantees, and verification. |
| Docs, skills, or tooling | Summary and Verification; explain non-obvious decisions and retained guidance boundaries. |
| Stack slice | Summary, Testing, and Stack: position, base-PR link, this slice's effect. Link the head instead of repeating the full feature description. |

For persistence, backup, CloudKit, or wire-format changes, explain compatibility with old data and parallel installs, any losses, and required upgrade order.
Call out API or data breaks explicitly. Include rollout or follow-ups when activation or ship order depends on another PR.
If the branch changes Linear issues or `MODULE_AUDIT.md`, include **Backlog reconciliation** with issue links and remaining work.
Consult merged examples only if the needed shape remains unclear.

#### Section semantics

Keep **Summary** focused on the resulting behavior; use **Why** for the previous problem and **Design decisions** for choices and rejected alternatives.
State when a temporary assumption should be reconsidered. Cover relevant onboarding, settings, failure, and edge-case behavior.
In **Testing**, give exact commands, counts, and the behavior exercised. Link source for inspection-only conclusions; state skipped checks and why.
Use **Review focus** for subtle behavior, incomplete migrations, assumptions about main, and remaining validation limits.

#### Guide the review

For changes spanning layers, give a short reading route through the central contract, implementation, integration, and test, stating what each establishes.
Use a compact Situation → Before → After table when branches or recovery behavior benefit from comparison.
For stacks or multiple consumers, state whether this slice adds groundwork or activates behavior, its affected entry points/audiences/data, and any prerequisite.
Prefer inline review comments for concerns about specific lines.

#### Explain API and architecture changes

Name the important API additions, changed contracts, removals, replacements, and affected callers. Omit exhaustive symbol inventories.
Use one or two short, language-tagged examples when needed to show composition, ownership, injection, or calling flow.
Use actual names, labels, and async/error contracts; explicitly mark omitted setup or illustrative future code.
Link the owning source. Scale examples to the change and omit API sections when they add no context.

#### Explain visible changes

For new screens or meaningful UI changes, show a small representative set of screenshots or snapshots, usually one to three.

- Use the reviewed revision and synthetic/demo data. Follow [building-ui](../../building-ui/SKILL.md) and [running-tests](../../running-tests/SKILL.md) for capture and review.
- For visual fixes or redesigns, label Before/After images with matching device, appearance, data, and framing.
- Caption the behavior, fixture/live capture, revision, and relevant settings. Include descriptive alt text and a full-resolution link.
- Use persistent GitHub attachments or revision-pinned URLs returning image bytes, including LFS images. Avoid local paths, expiring artifacts, and copies committed only for the description.
- Open the published PR to check images, captions, and links. Replace stale images after UI changes.
- Images do not establish live interaction, motion, or VoiceOver behavior. If useful images cannot be captured or published, state the reason and remaining validation limit.

#### Explain complex flows with diagrams

Use a compact Mermaid diagram when prose obscures ownership, data flow, or lifecycle. Each diagram should answer one question.
Name real components and relevant failure, cancellation, fallback, or retry paths. Distinguish durable/in-memory state and async/atomic operations.
State assumptions and omissions; do not imply guarantees such as cross-device atomicity that the implementation lacks.
Link the owner and trace the diagram against current code; refresh it after changes. Diagrams supplement API examples and validation evidence.
Verify syntax and rendering when a renderer is available; otherwise record the rendering limit.

#### Template hygiene

Populate retained sections and remove empty headers or stub bullets. Refresh the description when the final implementation changes its scope.
