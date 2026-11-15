# PR descriptions

### Writing the PR body

Squash merges on `main` use **PR title → commit subject** and **PR body → commit
body** — the body is what `git show` reads months later. Write for someone
bisecting or reconstructing *why*, not for the conversation that produced the
branch.

- **Title:** prefer `type(scope): imperative description` when it fits — the squash
  commit subject on `main`. Use the same **types** and **scopes** as
  [BACKLOG.md](../../../../BACKLOG.md) (`feat`, `fix`, `refactor`, `docs`, …;
  `WhereUI`, `WhereCore`, `Periscope`, …). Prose titles are fine for
  cross-cutting work that doesn't have one scope (`Add demo mode…`). Branch
  commits stay bisectable narrative. Only the PR title needs this shape.
- **End state, not a changelog:** describe what the repo looks like after merge,
  not commit-by-commit or chat-by-chat progress.
- **Explain what the diff doesn't show** — motivation, rejected alternatives,
  trade-offs, follow-ups that aren't obvious from the code alone.

#### Pick a tier

Choose only the explanations that resolve a real review question.
Add them within the existing sections.
Omit inapplicable material without `N/A` placeholders.

| Tier | When | Keep | Add when warranted |
| --- | --- | --- | --- |
| Small | Obvious fix, 1–2 modules, no design choices | Summary (2–4 end-state bullets), Testing | Why and Review focus for subtle behavior |
| Medium | Feature or behavior change | Summary, Why, Review focus, Testing | User-facing / Internal split in Summary when mixed |
| Large | Architecture, multi-module feature, new protocol | Summary or Problem + Changes, Why, Design decisions, Product behavior or Architecture, Review focus, Testing | Breaking changes and Compatibility for persistence, backups, CloudKit, or wire formats; Rollout / follow-ups when ship order or another PR matters; Stack or prototype rounds |
| Refactor or migration | Ownership, API, or stored-shape changes | Problem or Summary, Changes, Design decisions, Review focus, Testing | Breaking changes and Compatibility for stored-shape or backup changes |
| Docs, skills, or repo tooling | Guidance or tool maintenance | Summary, Testing or Verification | Why for non-obvious changes; Review focus for moved/retained guidance boundaries |
| Stacked PR | One slice in a chain | Summary, Testing, Stack (position, base-PR link, this slice's effect) | Link the stack head; do not repeat the full feature description |

If the branch changes Linear issues or `MODULE_AUDIT.md`, add **Backlog reconciliation** with affected issue links and remaining work.
Only if a required shape remains unclear, open merged PRs for examples.

#### Section semantics

- **Summary** — end-state bullets (add/keep/preserve/migrate/remove). Not a
  commit log. When a PR mixes user-visible and internal work, prefix bullets
  with **User-facing:** or **Internal:** so `git log` readers can scan quickly.
- **Why / Problem** — what was wrong or missing before. Link prior PRs when
  building on them.
  For bug fixes, include the failure trigger and the visible symptom or relevant error text.
  Use terms that future readers can search for.
- **Changes / Architecture / Product behavior** — structure, behavior, and data flow, grouped by subsystem with bold labels.
  For architecture changes, explain key types, invariants, and ownership.
  For refactors or migrations, explain what moved, what was removed, and what the compiler now enforces.
  For product changes, cover onboarding, settings, failures, and edge cases.
- **Screenshots** — selected images that explain visible behavior. Follow
  [Explain visible changes](#explain-visible-changes). When images add no useful context, omit this section.
- **Primary APIs** — important additions, changed contracts, and removals, with
  short usage examples. Follow [Explain API and architecture changes](#explain-api-and-architecture-changes).
- **Design decisions / Trade-offs** — explicit choices and what was rejected.
  When a choice depends on a temporary assumption, state what evidence or condition warrants reconsideration.
- **⚠️ Breaking changes** — wire-format, persistence, backup, CloudKit schema,
  or API breaks. What existing data/installs lose or must do. Delete the section
  when there are none.
- **Compatibility** — how old data, backups, or parallel installs behave through
  the change. Required upgrade order. Delete when N/A.
- **Review focus** — subtle behavior, incomplete migrations, assumptions about
  `main`. Prefer inline review comments for specific lines.
- **Testing** — exact commands with pass counts and the relevant behavior or invariant they exercise.
  Link source locations for conclusions based only on inspection.
  For skipped checks, state
  **what** and **why**.

#### Guide the review

- For changes across several files or layers, add a short reading route to **Review focus**.
  Link the central contract, implementation, integration, and relevant test in a useful order.
  Choose only the useful starting points.
  State what each starting point establishes.
- For behavior changes with meaningful branches, add a compact **Situation → Before → After** table to **Product behavior** or **Summary**.
  Include the ordinary case and relevant failure, cancellation, or recovery cases.
  Use scenarios from the implemented behavior.
- For stacked PRs or changes with several consumers, explain this PR's effect after merge.
  Put this explanation in **Summary** or **Stack**.
  State whether the slice adds groundwork or activates reachable behavior.
  Identify affected audiences, entry points, extensions, or existing data where relevant.
  Name any prerequisite PR or activation condition.

#### Explain API and architecture changes

When a PR changes APIs or architecture, show enough structure to understand the
change without opening the diff.

- Summarize the primary API additions, changes, and removals in a compact table
  or bullets. Name each API's role and affected callers. For a removed or
  replaced API, name its replacement or explain how callers now work.
- Focus on entry points, important state/value types, and changed boundaries.
  Omit exhaustive symbol lists and implementation helpers.
- Add one or two short, language-tagged code samples showing composition,
  injection, or the main calling flow. Use a before/after pair when it clarifies
  an API replacement. Explain who owns the components and how they connect.
- Use the current implementation's names, argument labels, and async/error
  contracts. Mark omitted setup or illustrative future-feature code explicitly.
  Do not present invented helpers as APIs shipped by the PR.
- Link the key source files when readers need more detail. Keep the examples
  focused on the design rather than copying full implementations.
- Scale this material to the change. A small API edit can use one bullet and a
  few lines of code. Omit API sections for changes with no relevant API impact.

#### Explain visible changes

For new screens or meaningful UI changes, include screenshots or snapshot images that explain the result.

- Choose a small set of representative images, usually one to three. Show the main flow and relevant states without reproducing the full snapshot matrix.
- Prefer existing snapshots that match the reviewed revision, or capture the running feature. Use synthetic or demo data.
  Follow [building-ui](../../building-ui/SKILL.md) and [running-tests](../../running-tests/SKILL.md) for capture and review.
- For a visual fix or redesign, label comparable images **Before** and **After**.
  Keep their device, appearance, data, and framing consistent.
- Caption each image with the behavior to inspect. Identify the snapshot fixture or live capture, revision, and relevant device or appearance settings.
  Provide descriptive alt text. Keep images readable inline and link to the full-resolution images.
- Use persistent GitHub attachments or revision-pinned repository image URLs that return image bytes, including Git LFS assets.
  Avoid local paths, expiring artifact URLs, and extra image copies committed only for the PR body.
- Open the published PR and check each image, caption, and link. When the relevant UI changes, replace stale images.
- Keep visual explanation separate from testing claims. A snapshot fixture does not establish live interaction, motion, or VoiceOver behavior.
- If useful images cannot be captured or published, state the reason and the remaining visual validation limit.

#### Explain complex flows with diagrams

When prose hides important relationships, add a compact diagram beside the architecture explanation.
Backend-heavy features often qualify: multi-owner work, persistence, synchronization, cancellation, retries, and recovery.
Skip diagrams for simple changes or facts that a short paragraph or table explains clearly.

- Prefer fenced `mermaid` in the PR body so the diagram stays editable and renders on GitHub.
- Use a flowchart for decisions and data flow, a sequence diagram for ownership and ordering, or a state diagram for lifecycle.
- Give each diagram one question to answer. Split unrelated flows instead of drawing the entire system.
- Name the real components and label important transitions. Distinguish durable writes from in-memory state and asynchronous handoffs from atomic operations.
- Include the failure, cancellation, fallback, or retry paths that affect the changed contract. Do not show only the happy path.
- State omitted details and assumptions beside the diagram. Never imply cross-device atomicity or guarantees that the implementation does not provide.
- Link the source that owns the flow. Keep API examples and validation evidence alongside the diagram, not replaced by it.
- Trace the diagram against the current implementation before posting. Refresh it when review changes the flow.
- Verify Mermaid syntax and inspect rendering when a renderer is available. Otherwise state the rendering limitation in validation.

#### Template hygiene

- Populate every section you keep. **Delete unused section headers** and stub
  bullets before opening or updating the PR. Empty headers pollute the squash
  commit body.
- Refresh the title/body once the branch outgrows them. Fold into any human
  edits rather than overwriting them.
