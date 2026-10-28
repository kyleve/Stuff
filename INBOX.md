# Inbox

Unverified notes, straight from a human. Write badly on purpose: one bullet per
thought, no tags, no citations, no research. Getting it out of your head before
it evaporates is the entire job of this file.

Nothing here has been checked against the source, so an entry may turn out to be
already fixed, already filed, or simply wrong. That's expected — it's what the
pipeline is for.

## Usage

- Add a bullet under [Open](#open). Hint at an area (`WhereUI:`, `Periscope:`) if
  you already know it; the pipeline routes it either way.
- Don't tag, prioritize, cite, or research it. That's the pipeline's job, and
  doing it by hand here just means doing it twice.
- Agents **read from this file and promote out of it** — they never file new
  items here. Agent-found work goes straight into the right `TODOs.md`.

The `todo-triage` skill drains this file: it verifies each entry against current
source, expands it into the item format that [`TODOs.md`](TODOs.md) defines, and
files it in the lowest `TODOs.md` spanning what it touches. A filed entry leaves
this file and keeps a `(human <date>)` origin tag in the backlog, so you can
always find your own. An entry the pipeline declines moves to
[Triaged](#triaged) with a one-line verdict — nothing is deleted silently.

# Open

# Triaged

Entries resolved without filing a backlog item, kept so a note you wrote never
just disappears. Prune this section when it stops being interesting.
