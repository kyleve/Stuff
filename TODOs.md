# Repo todos

The cross-cutting backlog: items that span more than one area, plus the ones that
belong to the repo itself — dev scripts, CI, the Bumper Bowling rules, repo-level
docs. Anything scoped to a single area lives in that area's own `TODOs.md`.

This file also owns the **item format** and the **placement rule** every
`TODOs.md` in the repo follows; the others point here rather than restating them.

## Format

One item per bullet:

```
- <type>(<Scope>) [<effort>]: <title> — <body, citing file:line>. (<origin> <date|ref>)
```

- **`<type>`** — a conventional-commit type: `feat`, `fix`, `refactor`, `perf`,
  `test`, `docs`, `design`.
- **`(<Scope>)`** — the module the work lands in (`WhereUI`, `PeriscopeTools`,
  `Bumper`, …). One `TODOs.md` usually covers several modules, so the scope says
  which; omit it in a file that covers exactly one.
- **`[<effort>]`** — `quick-win` (localized, lands in a small PR) or
  `needs-design` (broader refactor, policy choice, or cross-module contract).
  Grep either to pick up work. Omitted under `PX`, where the shape isn't known
  yet.
- **`<title> — <body>`** — what's wrong, then the evidence: the `File.swift:123`
  sites, why it matters, and the suggested fix. Always cite locations; a claim
  with nothing behind it can't be re-verified once the code moves.
- **`(<origin> <date|ref>)`** — where the item came from: `(human 2026-07-24)`,
  `(audit 2026-07-26)`, `(pr#107 review)`. This is the human/agent split, and it
  survives the rewrite an agent gives a promoted inbox note — so you can always
  see which items started as your own. Drop the date when it genuinely isn't
  known, as on items that predate this format: a bare `(human)` or `(agent)` is
  honest, a guessed date isn't.

Buckets carry priority. There is deliberately **no separate severity field**:
two priority axes can disagree, and then neither is trusted.

| Bucket | Meaning |
|--------|---------|
| `PX` | Exploratory — a direction worth thinking about, not yet a task |
| `P0s` | Must do |
| `P1s` | Should do |
| `P2s` | Nice to have |

Two more rules:

- **Nest a dependent task** under the item it depends on.
- **Never delete a completed item.** Move it to "Completed issues" at the bottom
  with a note on how it was closed.

Example:

```
- fix(WhereUI) [quick-win]: `CalendarDay.displayDate` resolves through
  `Calendar.current` (`DateRangeFormatting.swift:33`), so every day label renders
  ~543 years off on a Buddhist-era device. Take an explicit Gregorian calendar and
  thread `report.calendar` from the call sites. (audit 2026-07-26)
	- fix(Bumper) [quick-win]: Widen `where.gregorian_calendar` to the
	  implicit-member form — it filters on `base == "Calendar"`
	  (`.bumper/Sources/WhereProjectRules.swift:121`), so it enforces nothing.
	  (audit 2026-07-26)
```

## Where an item lives

An item goes in the **lowest** `TODOs.md` that spans every area it touches, up to
this one:

| File | Covers |
|------|--------|
| `TODOs.md` (this file) | Cross-area items, dev scripts, CI, Bumper Bowling, repo-level docs |
| `Where/TODOs.md` | The Where app and every module under `Where/` |
| `Shared/<Area>/TODOs.md` | That shared module or module group |

A WhereUI-only item belongs in `Where/TODOs.md`; one that spans WhereUI *and* the
repo-owned Bumper rules belongs here. An area gets its own file the first time it
has an item, and links back here for the format instead of copying it.

## How items get here

Raw, unverified notes go in [`INBOX.md`](INBOX.md) — one bullet, no tags, no
research. The `todo-triage` skill drains it: it verifies each entry against
current source, expands it into the format above, and files it in the right area.
Everything below has already been through that, so write new thoughts in the
inbox rather than here.

# Open issues

## PX (Exploratory)
- feat: Update the deployment target to iOS 27 — this lets us use `HistoryObserver` for CloudKit/SwiftData instead of the notification. Spans every target's minimum OS (`Package.swift`, `Project.swift`), so it sits here rather than in `Where/TODOs.md`. (human)

## P0s (Must do)
- fix(Bumper) [quick-win]: `where.gregorian_calendar` matches only an explicit `Calendar` base, so it enforces nothing. It filters `MemberAccessExprSyntax` on `base?.trimmedDescription == "Calendar"` (`.bumper/Sources/WhereProjectRules.swift:121`), which catches a spelled-out `Calendar.current` but not the implicit-member form (`calendar: Calendar = .current`, `startOfDay(in: .current)`) — and after the Gregorian call-site pass (`fe99dde`) the implicit form is the only one left in the tree. CI hard-gates `bumper lint` at `severity: .error` and is green, which confirms it: the rule reports nothing while production sites drift. Also match a no-base `MemberAccessExprSyntax` whose contextual type is `Calendar`, or add a lexical `.current` check scoped to calendar parameters and arguments. A rule that reads as enforced but enforces nothing is worse than a documented convention, because it stops anyone from looking. Pairs with the `CalendarDay.displayDate` P1 in [`Where/TODOs.md`](Where/TODOs.md). (audit 2026-07-26)
	- docs(Bumper) [quick-win]: Correct `.bumper/RULES.md:101` and `:143`, which claim three calendar violations and some preview-coverage violations are "left visible during this bootstrap". Neither exists — the lint gate is green, and `52f0136` closed the preview ones. Delete both paragraphs, and re-add the calendar one only if the widened rule genuinely finds drift. (audit 2026-07-26)

## P1s (Should do)

## P2s (Nice to have)
- perf(StuffTestHost) [needs-design]: Two loose ends in the shared test host, both reaching the root Tuist manifest, which is why they sit here rather than in a StuffTestHost file. The WhereCore-always-embedded build trade-off is documented and verified load-bearing at `Project.swift:256` — decide whether to keep documenting it or split the host so unrelated bundles don't pay for it. Separately, the scene configuration name is spelled twice, in `Shared/StuffTestHost/Sources/AppDelegate.swift:11` and `Project.swift:244`, so the two can drift silently. (audit 2026-07-26)

# Completed issues
