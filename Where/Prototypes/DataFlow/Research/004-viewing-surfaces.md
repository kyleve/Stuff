# Both viewing surfaces

Date: 2026-10-23.
Status: user decision recorded. Implementation implications proposed.
Source: follow-up discussion in the initiating conversation.

## User decision

The user selected both options: a separate Mac window and a view within Where.
Both surfaces are part of the prototype goal.
This decision supersedes the unresolved viewer-location choice in the initial brief.

## Proposed implications

Both surfaces need the same meaning for stages, relationships, identity, and outcomes.
Their layouts and controls can differ to fit their available space.
A shared observation contract can support that consistency without requiring a shared renderer.

The Mac surface needs a way to receive activity from the running app.
That design must describe connection state, reconnection, ordering, and capture gaps.
The in-app surface needs access to the active app world's observation session.
Both surfaces must identify which app session they show.

These are design implications, not a selected transport or module architecture.

## Still open

- Which real flow demonstrates the tool first?
- Which surface arrives first during implementation?
- Does the Mac window use a native app or a browser-based viewer?
- Does the first connection support the simulator, a physical device, or both?
- Which selection, filtering, and pause behavior must the two surfaces share?

Current decision: [D003](003-decisions.md#d003--support-both-viewing-surfaces).
