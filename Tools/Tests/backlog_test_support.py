"""In-memory Linear boundary for migration recovery tests."""

import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parents[1]))
from backlog_inventory import TEAM_ID, WORKSPACE, parse_file, estimate_creation_dates
from backlog_linear import LinearError


def manifest():
    source = "# Open issues\n## P1s\n- fix(Core) [quick-win]: Fix ünicode — preserve evidence. (human)\n\t- test(Core) [quick-win]: Cover the fix.\n# Completed issues\n- fix: Old fault. (resolved 2026-07-01)\n"
    entries = parse_file("Where/TODOs.md", source, "abc")
    estimate_creation_dates(entries)
    return {
        "source_revision": "abc",
        "team_id": TEAM_ID,
        "workspace": WORKSPACE,
        "entries": entries,
    }


class FakeLinear:
    def __init__(self):
        self.stored = {}
        self.label_store = []
        self.view_store = []
        self.creates = []
        self.fail_after_issue = False

    def team(self):
        return {
            "triageEnabled": True,
            "autoClosePeriod": None,
            "autoArchivePeriod": 12,
            "autoCloseParentIssues": False,
            "autoCloseChildIssues": False,
            "states": {
                "nodes": [{"name": name, "id": name} for name in ("Backlog", "Done")]
            },
        }

    def labels(self):
        return copy.deepcopy(self.label_store)

    def views(self):
        return copy.deepcopy(self.view_store)

    def issues(self):
        return copy.deepcopy(list(self.stored.values()))

    def create(self, entity, input_type, fields, values):
        values = copy.deepcopy(values)
        self.creates.append(entity)
        if entity == "issueLabel":
            parent = next(
                (
                    label
                    for label in self.label_store
                    if label["id"] == values.get("parentId")
                ),
                None,
            )
            item = {**values, "isGroup": values.get("isGroup", False), "parent": parent}
            self.label_store.append(item)
        elif entity == "customView":
            item = {**values, "slugId": values["id"], "team": {"id": TEAM_ID}}
            self.view_store.append(item)
        elif entity == "issueRelation":
            item = {**values, "relatedIssue": {"id": values["relatedIssueId"]}}
            self.stored[values["issueId"]]["relations"]["nodes"].append(item)
        else:
            item = {
                **values,
                "identifier": f"STU-{len(self.stored) + 1}",
                "url": "https://linear.app/issue/" + values["id"],
                "state": {"name": values["stateId"]},
                "team": {"id": TEAM_ID},
                "parent": {"id": values["parentId"]}
                if values.get("parentId")
                else None,
                "labels": {
                    "nodes": [{"id": label} for label in values["labelIds"]],
                    "pageInfo": {"hasNextPage": False},
                },
                "relations": {"nodes": [], "pageInfo": {"hasNextPage": False}},
                "createdAt": values.get("createdAt", "2026-11-09T00:00:00Z"),
                "completedAt": values.get("completedAt"),
                **dict.fromkeys(
                    ("assignee", "project", "cycle", "estimate", "dueDate")
                ),
            }
            self.stored[item["id"]] = item
            if self.fail_after_issue:
                self.fail_after_issue = False
                raise LinearError("Uncertain write: rate limit or timeout after commit")
        return copy.deepcopy(item)
