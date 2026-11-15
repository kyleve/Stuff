# Mobius workspace study

Open [index.html](index.html) in a browser. This is the second iteration: each PR is a logical workspace, presented as a tab or a window, containing independent review, source, research, and simulated-preview views. It is a self-contained offline mockup. No installation or account is needed. **Reset** or reloading restores the sample session.

To serve it locally from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Plans/2026-11-14-mobius/Prototype
```

Visit `http://127.0.0.1:8765`; stop the server when finished. The canvas selector previews layouts within the available browser width. Resizing the browser works too.

## Explore the workspace

1. PR 42 starts with a review, supporting source, and simulated preview in separate child views. Use **New view** to open another Review, Source, Research, or Preview. Multiple views of the same kind are supported.
2. In two Review views, choose different files or comparisons. Their navigation stays independent; marking a file reviewed updates shared progress for that PR. Source views have independent file selectors. Each Research view keeps its own query; results open a new Source view.
3. Use **Tabs / Windows** in the app bar to change how the PR workspaces are presented. It keeps the same workspace contents, child identities, progress, and focus. The window shells are simulated within the browser.
4. On wide layouts, **Tile**, **Float**, and **Focus** explore child arrangements. In Float, drag a title bar to move a view or use its corner to resize it. With the title focused, arrow keys move and Shift+arrow keys resize; the resize handle also accepts arrow keys.
5. Compact layouts show the focused child and a scrollable view selector while retaining the wider arrangement. Switch to a source, research, or preview child, leave for PR 43, and return: that child and the workspace arrangement are restored. Resuming a Review child starts its own selected file at the top.
6. Change the preview's sample state among results, empty, and loading. Add a second Preview to compare states. The content is explicitly simulated; no code is executing.
7. Close a child to remove that view while retaining PR progress. Closing an unfocused child does not steal focus, including in another visible workspace. Closing the last child leaves an empty workspace where **New view** starts another view. These are mockup behaviors, not a settled native scene-lifecycle specification.

The modes and default layouts are hypotheses to evaluate. This prototype does not commit every native platform to every mode, or define production scene ownership and synchronization.

## Try the return visit

1. In PR 42, mark `Parser.swift` and `Stable.swift` reviewed at v1; leave `Store.swift` unreviewed.
2. **Simulate push** advances only that PR to v2. In Remaining, Parser shows its new edit, Store shows its full current PR diff, and Stable has no remaining changes.
3. Open Parser's full PR diff, then return to Remaining. Its baseline stays at v1 until **Mark reviewed**. Marking it at v2 updates all review views in that PR while preserving each view's selected file and comparison.
4. Open two Research views with different queries, supporting source, and a review draft. Switch to PR 43 and back. The PRs remain independent even though their fixtures share file paths.
5. Leave while a non-review child is focused and confirm it returns focused. Separately, scroll a review, leave it, and resume it: the same selected file opens at its top.

## Boundaries and retained history

The current artifact has two synthetic PRs and two prepared revisions. Search covers four sample files. Reading, navigating, changing presentation, and opening views never mark files reviewed. Drafts are private session notes; nothing is submitted. There is no editing, cloning, or fork feature: the user clarified that “fork” meant “view.”

Prepared code comparisons do not implement Git or represent compilable application code. There is no authentication, backend, durable storage, provider integration, actual OS windowing, native execution, or device sync. The mockup state schema is not a production schema. The experiment stays executing until the second user evaluation is recorded in [plan 01a](../01a-workspace-prototype.md).

The first iteration flattened a workspace into one document-tab group. The user's evaluation required the ownership/presentation correction above. Its [runnable artifact](iteration-01.html) is byte-for-byte the original [revision `2e3653877`](https://github.com/kyleve/Stuff/blob/2e3653877bf141964805d417eac0b94c03a24c6a/Plans/2026-11-14-mobius/Prototype/index.html). Its [verification record](evidence/verification.json) and [desktop](evidence/desktop.png), [tablet](evidence/tablet.png), and [phone](evidence/phone.png) captures remain historical evidence. They are not acceptance of the revised model.

## Iteration 2 evidence

Live Chromium captures in light appearance, at 1× device scale, using synthetic data:

| Capture | Viewport | What to inspect |
| --- | --- | --- |
| [Tiled children](evidence/iteration-02/desktop-tiles.png) | 1440 × 1000 | One logical PR workspace containing review, source, and preview views together. |
| [Outer workspace windows](evidence/iteration-02/desktop-windows.png) | 1440 × 1000 | Two distinct PR window shells, each retaining its own child collection and focus. |
| [Floating children](evidence/iteration-02/tablet-float.png) | 834 × 1112 | Bounded freeform placement with a simulated preview focused over code views. |
| [Compact preview](evidence/iteration-02/phone-preview.png) | 390 × 844 | Return to the last-focused preview; other views remain available in the selector. |

[Verification record](evidence/iteration-02/verification.json) identifies the final source and checks. Complete browser scenarios passed at all three sizes, covering independent same-kind views, shared review progress, outer presentation changes, arrangement/focus restoration, per-child review resumption, simulated-preview state, closure/recovery, and Reset. Pointer/touch taps, keyboard submission, and wide-layout pointer/keyboard movement and resizing were exercised. Checked states had no runtime/load errors, external requests, or axe WCAG 2/2.1 A/AA violations.

Fresh independent review verified corrections for floating order, background/inactive-workspace closure, empty-workspace focus, preview keyboard scrolling, and search submission. A generic input-change rerender detached the search form before Enter could submit it; the handler now owns only its select controls. Modal dismissal completes synchronously so queued close events cannot replace a newly active form. The compact selector keeps its active child visible after rendering.

The observations are browser evidence, not native, VoiceOver, actual execution, persistence, provider, or sync acceptance. Automated accessibility scans are not a complete accessibility audit.
