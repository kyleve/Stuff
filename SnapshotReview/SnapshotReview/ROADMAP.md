# Snapshot Review roadmap

## First version

- Browse cases in a grid or inspect one image with zoom and scrolling.
- Start with regular light images. Switch appearances with segmented controls or keyboard shortcuts.
- Preserve zoom and proportional scroll position across variants.
- Review and advance through a stable queue. Skip, return, and see progress.
- Restore the last folder and review context.
- Add notes and todos to an image or a point. Keep reviewed and open-todo counts separate.
- Undo and redo review edits. Copy open todos as Markdown for an engineer or coding agent.
- Save versioned JSON beside each suite. Detect content changes and external file edits.

## Later: compare with the last reviewed image

A fingerprint identifies a changed file but cannot display the previous image.
Historical comparison can offer side-by-side images, an overlay slider, and a before/after toggle.
This needs either retained reviewed images or reliable retrieval from Git. The storage choice remains a future design decision.

The actionable proposal lives in [the comparison backlog item](../TODOs.md#p2s).
Failure-image imports, capture controls, baseline approval, accounts, and cloud collaboration remain outside the first version.
