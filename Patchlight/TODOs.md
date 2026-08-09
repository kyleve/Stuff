# Patchlight todos

The item format and placement rule live in the root [`TODOs.md`](../TODOs.md).

# Open issues

## PX (Exploratory)
- feat(Patchlight): Evaluate a backend for webhooks, push notifications, team-shared state, and background inbox analysis — v1 is explicitly direct-client/local-only (`README.md:9-15`), so this needs a separate trust, operations, and privacy design. (human 2026-08-08)
- feat(PatchlightCore): Evaluate local checkout/agent harnesses after a sandboxed or server execution model exists — Cursor CLI/Background Agents, Claude Code, and OSS harnesses assume repository/process capabilities outside the Catalyst sandbox; keep v1's bounded read-only HTTP tools. See [Cursor headless CLI](https://docs.cursor.com/en/cli/headless) and `Patchlight/AGENTS.md:9-12`. (human 2026-08-08)
- feat(PatchlightCore): Evaluate more providers and local models — Gemini, OpenRouter, and on-device inference need explicit schemas, privacy UI, usage reporting, and capability tests beside the v1 OpenAI/Anthropic adapters (`README.md:12-15`). (human 2026-08-08)

## P0s (Must do)

## P1s (Should do)
- feat(PatchlightCore) [needs-design]: Complete reviews beyond GitHub's 3,000-file REST ceiling — the API caps pull-request file responses, so a fetched subset must stay visibly incomplete until an alternate Git data strategy can prove completeness. See [GitHub pull-request files API](https://docs.github.com/en/rest/pulls/pulls) and `README.md:28-32`. (human 2026-08-08)
- feat(Patchlight) [needs-design]: Support GitHub Enterprise Server and multiple simultaneous GitHub accounts — v1 fixes GitHub.com and one account (`README.md:9-10`); this widens endpoint trust, OAuth/App configuration, scope switching, storage identity, and sign-out semantics together. (human 2026-08-08)

## P2s (Nice to have)
- feat(PatchlightUI) [needs-design]: Add an iPhone UI — v1's target and snapshot matrix are deliberately iPad/Catalyst-only (`PatchlightUI/README.md:10-12`). (human 2026-08-08)
- feat(PatchlightUI) [needs-design]: Add syntax highlighting, full GFM, and evaluate parser packages — v1 uses native plain text plus built-in Markdown and needs measured viewport-lazy rendering before adding parser cost (`PatchlightUI/AGENTS.md:9-12`). (human 2026-08-08)
- feat(Patchlight) [needs-design]: Add one-window-per-PR and richer multiwindow restoration — v1 owns one app window (`README.md:9-10`), so workspace identity and restoration need a new scene contract. (human 2026-08-08)
- feat(PatchlightCore) [needs-design]: Add AI inbox prefetch/ranking — deterministic dashboard ranking intentionally avoids sending unopened PRs to providers (`README.md:11-15`). (human 2026-08-08)
- feat(PatchlightCore) [needs-design]: Ingest real CI coverage — v1 can infer tests only from configured paths and changed test evidence; checks APIs do not provide line coverage (`PatchlightCore/README.md:3-13`). (human 2026-08-08)
- feat(PatchlightCore) [needs-design]: Add persistent learning and repository-shared correction rules — v1 corrections are per-head local safety overrides, not training data or a shared policy (`PatchlightCore/AGENTS.md:7-11`). (human 2026-08-08)
- feat(Patchlight) [needs-design]: Add background notifications without a Patchlight backend — polling and iOS background limits cannot promise a timely review inbox; define an honest delivery model first (`README.md:12-15`). (human 2026-08-08)
- feat(PatchlightCore) [needs-design]: Add merge, dismiss-review, administration, reactions, and published-comment editing/deletion — v1's write boundary is deliberately review/comment/viewed-only (`PatchlightCore/Sources/Interfaces.swift:111`). (human 2026-08-08)
- feat(ImageDiffKit) [needs-design]: Add non-PNG snapshot formats and advanced comparison tolerances — v1 routes PNG conventions and offers exact local RGBA comparison/heatmaps (`../Shared/ImageDiffKit/README.md:3-14`). (human 2026-08-08)
- refactor(Scripts) [needs-design]: Abstract `Where/install`, `Ledger/install`, and future Patchlight distribution only after the third workflow exists — concrete common signing/install behavior is not yet observable, so premature sharing would encode guesses (`../AGENTS.md:212-218`). (human 2026-08-08)

# Completed issues
