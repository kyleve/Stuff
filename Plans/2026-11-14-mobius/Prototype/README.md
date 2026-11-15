# Mobius workspace study

Open [index.html](index.html) in a browser. This third iteration keeps each PR as a logical workspace with independent review, source, research, and simulated-preview views, and gives their content more space through compact controls. It is self-contained and offline; no installation or account is needed. Reloading or **Reset** restores the sample session.

To serve it locally from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Plans/2026-11-14-mobius/Prototype
```

Visit `http://127.0.0.1:8765`; stop the server when finished.

## Find the controls

- **Workspace bar:** switch between **Search #42** and **Restore #43**. The comment icon opens the PR's private review draft; **+** adds another Review, Source, Research, or Preview.
- **Workspace options (…):** inspect full PR metadata and progress, select **Open views**, arrange children with **Tile / Float / Focus**, or change outer workspace presentation with **Tabs / Windows**. Compact widths retain the wider arrangement while showing the focused child.
- **Current view:** wide child title bars identify the file or view. On compact layouts, the title is also the view selector. Use it to switch children; **×** closes the selected view. **Open views** also lets you choose or close any child without activating another one.
- **Review:** on wide layouts, click the filename to choose another file. On compact layouts, use the folder button. The comparison button states what is actually displayed—**Full PR diff**, **New edits since v1**, or **No remaining changes**—and opens Remaining / Full PR choices. **Mark reviewed** explicitly advances only that PR/file baseline.
- **Source:** use the filename control (or compact file selector) to browse sample source. **Review file** opens another review child for changed files. Research queries remain independent and results open new Source children.
- **Float:** drag the kind icon at the left of a child's title bar, or use its resize corner. With the move icon focused, arrow keys move and Shift+arrow keys resize; the resize handle also supports arrow-key resizing.
- **Sample controls:** expand **Sample data · Controls** above the workspace for Canvas width, each PR's **Simulate push**, and **Reset**. Escape closes the panel and returns focus. Preview content remains explicitly **Simulated**.

Dialogs close through Escape or their close button. These controls and layouts are hypotheses to evaluate, not commitments for every native platform.

## Try the return visit

1. In PR 42, mark `Parser.swift` and `Stable.swift` reviewed at v1; leave `Store.swift` unreviewed.
2. In sample controls, **Simulate push** for PR 42. Remaining now shows Parser's new edits and Store's full PR diff; unchanged Stable has no remaining work. Full context remains available from the comparison control.
3. Open two Review children with different files/comparisons. Their navigation stays independent; marking a file updates the shared PR baseline in both views. A caught-up view remains on its selected file.
4. Add multiple Research or Preview children, giving each a different query or simulated state. Change outer Tabs / Windows and return between PRs. Child identities, arrangement, progress, drafts, and last-focused view stay with their workspace.
5. Leave while a source, research, or preview is focused, and confirm it returns focused. Separately scroll a review, leave it, and resume it: that child's selected file opens at the top.
6. Close a background child, then the last child. Background closure keeps active focus; an empty workspace retains PR progress and can open another view.

## Iteration 3 evidence

The same initial Parser comparison was rendered before/after at matching viewports, light appearance, and 1× scale. The post-push incremental comparison was measured separately and has the same pane geometry. Measurements below are rounded to the nearest CSS pixel; [verification.json](evidence/iteration-03/verification.json) retains exact scroll-pane top/height and first-code-row top values.

| Viewport | Review pane height, before → after | First code-row top, before → after | Matched captures |
| --- | --- | --- | --- |
| 1440 × 1000 | 413 → 765 | 525 → 203 | [Before](evidence/iteration-03/desktop-before.png), [after](evidence/iteration-03/desktop-after.png) |
| 834 × 1112 | 535 → 877 | 515 → 203 | [Before](evidence/iteration-03/tablet-before.png), [after](evidence/iteration-03/tablet-after.png) |
| 390 × 844 | 216 → 648 | 568 → 195 | [Before](evidence/iteration-03/phone-before.png), [after](evidence/iteration-03/phone-after.png) |

Code text increased from 10px to 12px. Visible buttons in the initial phone state measure at least 44 × 44px. The gain comes from removing repeated bands and disclosing secondary controls.

Additional captures: [phone new edits](evidence/iteration-03/phone-incremental.png), [workspace windows](evidence/iteration-03/desktop-windows.png), [tablet float](evidence/iteration-03/tablet-float.png), [phone preview](evidence/iteration-03/phone-preview.png), and [workspace options](evidence/iteration-03/phone-options.png).

Complete browser scenarios passed at all three sizes using Playwright 1.64.1 / Chromium 156.0.8078.4. They cover independent child navigation, shared PR progress, outer presentation, arrangement/focus restoration, review file-top resumption, remaining/full comparisons, drafts, source-to-review, preview states, add/close/recovery, and Reset. Relocated controls were exercised by pointer/touch and keyboard, including Escape/focus return and Canvas changes. Five checked states per size had zero axe WCAG 2/2.1 A/AA violations; no page/console/load errors, external requests, or document overflow occurred.

Fresh independent review rechecked last-child dialog focus recovery, title accessible names, and immediate dialog reopening. The native close event is queued: a stale event must not dismiss a newly opened dialog. Five immediate close → reopen → Research → Enter trials passed. Floating children are contained beneath prototype controls; those controls stayed reachable after 40 view raises. Standalone file loading, inline JavaScript syntax, archive byte identity, local links, and diff whitespace also passed.

The checks are ad hoc browser evidence, not retained CI tests. Default repository web lint globs do not cover this HTML. Native tests, snapshots, and SwiftFormat are outside this browser-only slice. Automated accessibility scans do not establish VoiceOver or a complete accessibility audit. The third user evaluation remains pending in [plan 01a](../01a-workspace-prototype.md).

## Boundaries and retained history

Two synthetic PRs, two prepared revisions, and four searchable sample files keep the study bounded. Reading, navigation, presentation, and view creation never mark files reviewed. Drafts are private session notes; nothing is submitted. “Fork” was clarified as “view,” so there is no editing, cloning, or fork feature.

Prepared comparisons do not implement Git or compilable app code. There is no authentication, backend, durable storage, real OS windowing, execution, provider integration, or device sync. The mockup state schema is not a production schema.

- [Iteration 1](iteration-01.html) exactly preserves [revision `2e3653877`](https://github.com/kyleve/Stuff/blob/2e3653877bf141964805d417eac0b94c03a24c6a/Plans/2026-11-14-mobius/Prototype/index.html), its [verification record](evidence/verification.json), and original captures. The user found that it flattened a workspace into a document-tab group.
- [Iteration 2](iteration-02.html) exactly preserves [revision `e1c1059cf28`](https://github.com/kyleve/Stuff/blob/e1c1059cf28a2954a0513d2514e7d0b7be9c34dd/Plans/2026-11-14-mobius/Prototype/index.html) and its [separate evidence](evidence/iteration-02/verification.json). The user found the revised ownership model improved but requested less stacked chrome, leading to this pass.

Earlier evidence remains historical; it does not validate the changed controls or establish native product acceptance.
