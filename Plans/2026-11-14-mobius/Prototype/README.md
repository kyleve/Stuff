# Mobius workspace study

Open [index.html](index.html) in a browser. It is a self-contained, offline mockup using synthetic PRs; no installation or account is needed. Changes live only in memory. **Reset** or reloading restores the initial fixture.

To serve it locally from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Plans/2026-11-14-mobius/Prototype
```

Visit `http://127.0.0.1:8765`; stop the server when finished. The canvas selector previews narrow and wide layouts within the available browser width. Resizing the browser works too.

## Try the return visit

1. In PR 42, mark `Parser.swift` reviewed. Choose `Stable.swift` and mark it reviewed. Leave `Store.swift` unreviewed. On a phone, the sidebar button beside the current filename opens the file list.
2. Use **Simulate push**. Choose Parser in **Remaining**: only its new edit appears. Store shows its full current PR diff. Stable has no remaining work and remains accessible through **Full PR diff**.
3. Open Parser’s full PR diff, then return to remaining work. Its reviewed baseline stays at v1 until you explicitly mark it reviewed again. Marking it at v2 keeps the file visible with a caught-up message.
4. Open **Browse supporting source**, then the repository search button. Search for `WorkspaceID` and open `Reference.swift`. These become tabs within the same PR workspace.
5. Save a review draft. Return to a long full diff, scroll down, and switch to PR 43. On phone and tablet, the sidebar button beside the PR title opens workspaces.
6. Return to PR 42: the last review file opens at its top; its reference/search tabs, query, draft, and progress remain. PR 43 has its own state, even though it shares the sample file paths.

## Fixture boundaries

Each PR starts at v1 with three unreviewed files. A single simulated push advances only the active PR to v2. It changes Parser and Store; Stable is unchanged. Marking a file updates only that PR/file’s baseline. Navigation, comparison selection, reading source, search, and refresh do not mark files reviewed.

The code and comparisons are prepared samples, not an implementation of Git diff or compilable application code. Search covers four sample files. Refresh reports the current sample revision; only Simulate push advances it. Drafts are private session notes with no submit action. There is no authentication, backend, durable storage, provider integration, native windowing, or device sync.

The layout is a hypothesis for evaluation. This artifact’s state schema is not a proposed production schema. The experiment remains executing until user feedback is recorded in [plan 01a](../01a-workspace-prototype.md).

## Evidence

Captured from Chromium in light appearance, at 1× device scale, after exercising both workspaces. Images are retained as the experiment’s design evidence, not native snapshot references.

| Capture | Viewport | What to inspect |
| --- | --- | --- |
| [Desktop](evidence/desktop.png) | 1440 × 1000 | Independent PR rail, retained source/search tabs, and full Parser context after the push. |
| [Tablet](evidence/tablet.png) | 834 × 1112 | File list beside Parser’s new edits since v1, with Store still unreviewed. |
| [Phone](evidence/phone.png) | 390 × 844 | Compact navigation and Store’s full PR diff after the push. Long code lines scroll horizontally within the code pane. |

[Verification record](evidence/verification.json) identifies the exact HTML content, viewports, checks, and limits. Browser automation exercised the sequence above, PR43’s own incremental comparison, reset, pointer and touch taps, keyboard search/marking, and drawer mode → Escape focus restoration. The three scenarios passed; checked states had no runtime/load errors, external requests, or axe WCAG 2/2.1 A/AA violations. These results do not establish native, VoiceOver, real Git, persistence, provider, or sync acceptance.
