# Mobius workspace study

Open [index.html](index.html) in a browser. This mockup explores compact PR workspaces with independent review, source, research, and simulated-preview views, grouped file kinds, suitable comparisons, and explicit PR-local skip/undo. PR workspaces can now close and reopen with their context retained. It is self-contained and offline; no installation or account is needed. Reloading or **Reset** restores the sample session.

To serve it locally from the repository root:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory Plans/2026-11-14-mobius/Prototype
```

Visit `http://127.0.0.1:8765`; stop the server when finished.

## Find the controls

- **Workspaces:** the persistent picker lists open and closed sample PR workspaces. **×** on a PR tab or outer window closes that workspace without losing its views, review/skip progress, or draft. **Reopen** restores it; closing the last workspace leaves a deliberate empty state with recovery. This does not close the GitHub PR.
- **Workspace bar:** switch between **Search #42** and **Restore #43** using PR tabs, or the **PR workspaces · Windows** selector when separate workspace windows are shown. The comment icon opens the PR's private review draft; **+** adds another Review, Source, Research, or Preview.
- **Workspace options (…):** inspect full PR metadata and progress, select **Open views**, choose **PR workspaces → Tabs / Windows**, and separately arrange **Views in Search #42 → Tile / Float / One view**. Float stays movable/resizable at every width; narrow Tile stacks views. Narrow sessions initially choose One view. Resizing and changing outer presentation preserve explicit selections and saved placement.
- **Current view:** Tile/Float title bars identify each child file or view. In One view, the title is also the view selector. Use it to switch children; **×** closes the selected view. **Open views** also lets you choose or close any child without activating another one.
- **Review:** in Tile/Float, click the filename to choose another file. In One view, use the folder button. The comparison button states what is actually displayed—**Full PR diff**, **New edits since v1**, or **No remaining changes**—and opens Remaining / Full PR choices. **Mark reviewed** explicitly advances only that PR/file baseline. The chooser groups Code, Documents, Localization, and Snapshots/assets; quiet groups start collapsed. Its Remaining / All filter changes the list without changing the comparison. Counts distinguish remaining, reviewed, and skipped files.
- **Skip:** the comparison menu offers **Skip for this PR** for a remaining file. Group **Skip N remaining** captures only currently remaining members; **Undo** removes their active skips. Already-current reviewed files are excluded. A skipped file stays accessible under All, with Undo; explicit Mark reviewed is also available in its comparison menu when actual content exists.
- **Content previews:** Documents show rendered Markdown plus exact changed link targets; Localization shows changed key/locale/value rows; Snapshots/assets show before/after fixture images and metadata. **Source** reveals the prepared raw diff. LFS is a badge, not a group. `Design.psd` has only pointer/metadata fallback and cannot be marked reviewed.
- **Source:** use the filename control (or One view file selector) to browse sample source. **Review file** opens another review child for changed files. Research queries remain independent and results open new Source children.
- **Float:** drag the title bar, including its filename/title or kind icon, or use its resize corner. A stationary filename click opens the chooser; the separate close/focus actions remain buttons. With the move icon focused, arrow keys move and Shift+arrow keys resize; the resize handle also supports arrow-key resizing.
- **Sample controls:** expand **Sample data · Controls** above the workspace for Canvas width, each PR's **Simulate push**, and **Reset**. A push to a closed workspace updates its fixture without reopening it; Reset deliberately restores both initial workspaces. Escape closes the panel and returns focus. Preview content remains explicitly **Simulated**.

Dialogs close through Escape or their close button. These controls and layouts are hypotheses to evaluate, not commitments for every native platform.

## Try the return visit

1. In PR 42, mark `Parser.swift` and `Stable.swift` reviewed at v1; leave `Store.swift` unreviewed.
2. In sample controls, **Simulate push** for PR 42. Remaining now shows Parser's new edits and Store's full PR diff; unchanged Stable has no remaining work. Full context remains available from the comparison control.
3. Open two Review children with different files/comparisons. Their navigation stays independent; marking a file updates the shared PR baseline in both views. A caught-up view remains on its selected file.
4. Add multiple Research or Preview children, giving each a different query or simulated state. Change outer Tabs / Windows and return between PRs. Child identities, arrangement, progress, drafts, and last-focused view stay with their workspace.
5. Leave while a source, research, or preview is focused, and confirm it returns focused. Separately scroll a review, leave it, and resume it: that child's selected file opens at the top.
6. Close a background child, then the last child. Background closure keeps active focus; an empty workspace retains PR progress and can open another view.

## Try grouped comparisons and skipping

1. Reset. Open the file chooser and inspect collapsed quiet groups and their counts. Open Documents → `README.md`, Localization → `Localizable.xcstrings`, and Snapshots/assets → `SearchResults.svg`. Switch Preview / Source without marking anything reviewed.
2. Mark `README.md` reviewed at v1, then simulate a push. Its new edits change only the link target: the rendered prose stays the same, while the target note and source diff expose the edit. Localization and image comparisons also use their own actual reviewed version when available.
3. Reset. Mark `Parser.swift` reviewed, then use Code **Skip 2 remaining** and Snapshots/assets **Skip 2 remaining**. Parser remains reviewed; only Store, Stable, SearchResults, and Design are skipped.
4. Simulate the v2 push. Store and SearchResults return because their contents changed. New `EmptyResults.svg` was never skipped. Unchanged Stable and Design stay skipped. Parser shows edits since its actual v1 review. Counts read **6 remaining · 0 reviewed · 2 skipped**.
5. Undo individual/group skips and confirm they do not create review receipts. Skip the changed Parser at v2: its actual reviewed version stays v1, and Undo restores that incremental comparison. Zero remaining with skips reports the skipped count separately.

## Close and reopen a workspace

1. In Search #42, mark a file reviewed, select another review file, save a draft, and open or arrange child views.
2. Use the **×** on Restore #43's outer tab/window. Search keeps its active child. Reopen Restore through **Workspaces**, then switch back to Search.
3. Close Search. Restore becomes active. Close Restore too: the screen has no active workspace and offers **Reopen a workspace**.
4. Reopen Search. Its same child instances, selected files/queries, layout/frames, review/skip receipts, and draft return. The last-focused child returns; a Review starts its selected file at the top. Reopening an already-open entry switches to it without duplication.

[Exact-source evidence](evidence/workspace-close/verification.json) pins HTML SHA-256 `c99c3a8670006ca787dd5880ff9e04834b777d682f1dca7515688f94c6cad89b`. Eleven focused scenarios pass in each of three sizes × Tabs/Windows; fresh independent review has no findings. Narrow touch/hit and active-drag closure pass; the coordinator also checks Chromium/WebKit at phone/desktop sizes. Twelve author and six independent selected WCAG scans pass. Nine visually inspected captures use PR42 v1 with Parser reviewed, Store selected, a draft saved, and Float; phone uses Tabs, tablet/desktop Windows, light appearance, 1× scale:

| Viewport | Retained picker | All closed | Reopened context |
| --- | --- | --- | --- |
| 390 × 844 | [Phone picker](evidence/workspace-close/phone-picker.png) | [Empty](evidence/workspace-close/phone-empty.png) | [Store and views](evidence/workspace-close/phone-reopened.png) |
| 834 × 1112 | [Tablet picker](evidence/workspace-close/tablet-picker.png) | [Empty](evidence/workspace-close/tablet-empty.png) | [Store and views](evidence/workspace-close/tablet-reopened.png) |
| 1440 × 1000 | [Desktop picker](evidence/workspace-close/desktop-picker.png) | [Empty](evidence/workspace-close/desktop-empty.png) | [Store and views](evidence/workspace-close/desktop-reopened.png) |

The workspace remains in memory only; reload/Reset restores the sample. Cross-device open/closed policy is undecided in this experiment. Earlier title-bar/layout/type results below remain historical. User evaluation is pending.

## Title-bar drag correction

Drag the filename/title or surrounding header to move a floating view. A stationary click (or less than 5px jitter) keeps the file chooser; a completed drag does not open it. Separate close/focus/source-review buttons retain their actions, as do keyboard movement and resizing.

The prior handler accepted only the icon. Matching +36/+80px title-text gestures now move the view at all three sizes: [phone before](evidence/iteration-04-drag/phone-before.png)/[after](evidence/iteration-04-drag/phone-after.png), [tablet before](evidence/iteration-04-drag/tablet-before.png)/[after](evidence/iteration-04-drag/tablet-after.png), [desktop before](evidence/iteration-04-drag/desktop-before.png)/[after](evidence/iteration-04-drag/desktop-after.png). Captures use PR42 v1, Float + Tabs, light appearance, 1× scale. Before uses published `7f89c2b5c`; after uses source SHA-256 `3f86c704db285b85cd504a148236aa464016fb37dd92e005256f27cadc98007d`.

[Focused verification](evidence/iteration-04-drag/verification.json) records three-size pointer/touch, threshold/click, independent-control, cancellation, keyboard/resize, and continuity checks; fresh independent review has no findings. The coordinator's scoped Chromium/WebKit checks also pass. Earlier layout/type evidence below is historical and retained unchanged. User reevaluation remains pending.

## Layout-options correction

The user found that selected Float did not match the rendered layout and that outer Windows looked like another form of inner Float. The old width rule silently hid all but one child at 680px or below; switching to Windows created 679px hosts even on a 1440px desktop. Windows also retained the tab-looking PR strip.

The corrected options distinguish **PR workspaces** from **Views in the named PR**. Explicit Float works at every width, explicit Tile remains non-overlapping (stacked when narrow), and One view is its own selection. Saved normalized placement is fitted for display without rewriting it on a resize; movement starts from the fitted frame so the first drag does not jump. Windows uses separate labeled PR containers and a workspace selector, not a tab strip. These remain simulated browser windows.

Matched initial PR42 v1 fixtures, light appearance and 1× scale:

| Case | Before | After |
| --- | --- | --- |
| Phone 390 × 844, Float + Tabs | [One child despite Float](evidence/iteration-04-layout/phone-float-before.png) | [Actual floating views](evidence/iteration-04-layout/phone-float-after.png) |
| Tablet 834 × 1112, Float + Windows | [Silent narrow fallback](evidence/iteration-04-layout/tablet-windows-before.png) | [Distinct PR windows and floating views](evidence/iteration-04-layout/tablet-windows-after.png) |
| Desktop 1440 × 1000, Float + Windows | [Misleading shared tab strip](evidence/iteration-04-layout/desktop-windows-before.png) | [Separate scopes and effective Float](evidence/iteration-04-layout/desktop-windows-after.png) |

[Scoped options](evidence/iteration-04-layout/desktop-options-after.png), [narrow Tile](evidence/iteration-04-layout/phone-tiles-after.png), and [content in a narrow floating view](evidence/iteration-04-layout/phone-asset-float-after.png) show the other changed states. [Verification](evidence/iteration-04-layout/verification.json) pins source SHA-256 `93018f2fb35d28edb72daab1089a28dd849727658259bd177aa248f68a2e5f5b`. Author checks cover 36 computed combinations; independent review covers 42 including 320px and both sides of the old boundary. Three-size real pointer/keyboard movement, resizing, handle reachability, saved-placement continuity, independent PR frames, focus/review-top return, and empty recovery pass. A requested 4px/6px first drag moved exactly that amount without changing size. The reviewer also exercised narrow touch movement. Fifteen author and twelve independent selected WCAG scans pass with no browser errors.

This is focused correction evidence. The prior type-fixture matrix below remains historical; its catalog and review/skip/comparison functions are byte-identical, and changed-path continuity/content checks passed. [Iteration 4 before this correction](iteration-04.html) exactly preserves published `e987835f6`. Evaluation of the corrected presentation remains pending.

## Iteration 4 feature evidence (before layout correction)

[Verification](evidence/iteration-04/verification.json) pins HTML SHA-256 `fe137ea8e41335bbb0c25a203f6b27aac689bcdb2ce725420a63ab5b50dc8b00`, the checks, capture hashes, and review corrections. Matching v1 full-comparison states use light appearance and 1× scale:

| Viewport | Grouped list | Documents | Localization | Snapshots/assets |
| --- | --- | --- | --- | --- |
| 1440 × 1000 | [Groups](evidence/iteration-04/desktop-groups.png) | [Markdown](evidence/iteration-04/desktop-documents.png) | [Changed values](evidence/iteration-04/desktop-localization.png) | [Images](evidence/iteration-04/desktop-assets.png) |
| 834 × 1112 | [Groups](evidence/iteration-04/tablet-groups.png) | [Markdown](evidence/iteration-04/tablet-documents.png) | [Changed values](evidence/iteration-04/tablet-localization.png) | [Images](evidence/iteration-04/tablet-assets.png) |
| 390 × 844 | [Groups](evidence/iteration-04/phone-groups.png) | [Markdown](evidence/iteration-04/phone-documents.png) | [Changed values](evidence/iteration-04/phone-localization.png) | [Images](evidence/iteration-04/phone-assets.png) |

Additional evidence: [skip then push](evidence/iteration-04/desktop-skip-push.png), [unavailable binary](evidence/iteration-04/phone-unavailable.png), and [link-only source edit since review](evidence/iteration-04/phone-document-source.png). The default Code pane retains iteration 3's exact top/height: desktop 203/765px, tablet 203/877px, phone 195/648px. The code-table top is measured separately from the first table row, whose collapsed border extends one pixel above it.

Complete prior workspace scenarios and new grouping/skip/type scenarios passed at all three sizes with Playwright 1.64.1 / Chromium 156.0.8078.4. Checks cover independent child files/queries/format/expansion, shared PR review and skip receipts, drafts, layout/focus return, review file-top resumption, new/changed/unchanged work, group membership snapshots, raw/rich basis agreement, link-only edits, missing binary content, and explicit absent-before images. Thirteen WCAG 2/2.1 A/AA axe states per size passed; no page/console/load errors, external requests, or document overflow occurred. Standalone file loading also passes.

Fresh independent review found and rechecked the individual Skip accessible-name mismatch and an object-size field mislabeled as pointer size. The corrected label was shortened to keep narrow tablet metadata readable; source views now explicitly identify pointer-only content. Group action labels include visible counts and “remaining.” No actionable findings remain. Unfiltered axe also reports inherited best-practice heading/landmark warnings outside the selected WCAG tags; these scans are not a complete accessibility or VoiceOver audit.

The two user-facing revisions prove v1 skip → changed/new v2 return, unchanged skip persistence, and reviewed-v1 → skipped-v2 baseline retention. A separate seeded policy assertion verifies that a later changed content identity selects the actual v1 review basis; it does not render or claim a third UI revision. All checks are ad hoc evidence, not retained CI guards. Default web lint excludes this HTML; native tests/snapshots and SwiftFormat are outside this slice. Fourth-round user evaluation remains pending in [plan 01a](../01a-workspace-prototype.md).

## Iteration 3 evidence (historical)

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

The checks are ad hoc browser evidence, not retained CI tests. Default repository web lint globs do not cover this HTML. Native tests, snapshots, and SwiftFormat are outside this browser-only slice. Automated accessibility scans do not establish VoiceOver or a complete accessibility audit. The third user evaluation requested the grouped-kind and explicit-skip iteration above.

## Boundaries and retained history

Two synthetic PRs and two prepared revisions keep the study bounded. Each PR has seven changed files at v1 and eight at v2, plus one supporting source file. Typed previews and diffs are deterministic prepared fixtures; they do not parse real Markdown/catalogs or fetch LFS objects. Reading, navigation, presentation, and view creation never mark files reviewed. Drafts are private session notes; nothing is submitted. “Fork” was clarified as “view,” so there is no editing, cloning, or fork feature.

Prepared comparisons do not implement Git or compilable app code. There is no authentication, backend, durable storage, real OS windowing, execution, provider integration, or device sync. The mockup state schema is not a production schema.

- [Iteration 1](iteration-01.html) exactly preserves [revision `2e3653877`](https://github.com/kyleve/Stuff/blob/2e3653877bf141964805d417eac0b94c03a24c6a/Plans/2026-11-14-mobius/Prototype/index.html), its [verification record](evidence/verification.json), and original captures. The user found that it flattened a workspace into a document-tab group.
- [Iteration 2](iteration-02.html) exactly preserves [revision `e1c1059cf28`](https://github.com/kyleve/Stuff/blob/e1c1059cf28a2954a0513d2514e7d0b7be9c34dd/Plans/2026-11-14-mobius/Prototype/index.html) and its [separate evidence](evidence/iteration-02/verification.json). The user found the revised ownership model improved but requested less stacked chrome, leading to iteration 3.

- [Iteration 3](iteration-03.html) exactly preserves [revision `58c13ac56`](https://github.com/kyleve/Stuff/blob/58c13ac56f87688548887172fef6f39e818bc819/Plans/2026-11-14-mobius/Prototype/index.html) and its [separate evidence](evidence/iteration-03/verification.json). The user then requested grouped kinds and explicit skip/resurfacing, leading to iteration 4.

- [Iteration 4 before the layout correction](iteration-04.html) preserves [revision `e987835f6`](https://github.com/kyleve/Stuff/blob/e987835f6a1dd18463eceaf8274673c8445036d5/Plans/2026-11-14-mobius/Prototype/index.html) and its grouped-content/skip evidence. User feedback then required selected layouts to match actual rendering, including Float at narrow widths.

Earlier evidence remains historical; it does not validate the changed controls or establish native product acceptance.
