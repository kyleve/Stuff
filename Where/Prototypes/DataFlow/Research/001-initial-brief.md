# Initial brief

Date: 2026-10-23.
Status: user intent recorded. Product and technical scope remain open.
Source: the initiating conversation.

## Agreed direction

The user wants a prototype visualization tool to watch real data flow live through Where.
The work will likely involve several PRs and an extended design discussion.
The user requested a plan file instead of a transient planning-mode response.
Research and discussion belong in a companion document folder for later reference.

This request establishes the goal and document workflow.
It does not select a viewer platform, graph design, event model, or transport.

## Candidate debugging questions

These questions are proposals for discussion:

- Where did a location sample go after the app received it?
- Which persisted change caused a report or widget to update?
- Why did an expected output remain unchanged?
- Which work waited, retried, failed, or became obsolete?
- Did several writes combine into one refresh?
- Which stored values or revisions contributed to the result?

Different questions need different evidence.
A component activity map shows which services are busy.
An operation trace shows what happened during one action.
Data lineage links inputs and revisions to their resulting outputs.
The first prototype needs a chosen question before it needs a general graph model.

## Proposed scope for an initial experiment

Use the running app and its normal services as the source of observed activity.
Start with one flow and enough detail to explain its outcome.
A manual day edit provides a repeatable candidate.
GPS ingestion provides a candidate with visible input, persistence, retries, and derived outputs.

The initial discussion considered an in-app viewer and a separate Mac viewer.
A separate viewer introduces a transport and connection lifecycle.
An in-app viewer shares the app process and its resource budget.
Update, 2026-10-23: the user selected both surfaces. See [004](004-viewing-surfaces.md).

## Questions for the next discussion

1. What information and interactions must both viewing surfaces share?
2. Which debugging question and real action define the first successful demonstration?
3. What must a node and an edge mean in that demonstration?

The [decision register](003-decisions.md) retains these questions and later choices.
