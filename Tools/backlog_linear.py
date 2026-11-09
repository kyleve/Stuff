"""Linear transport and restartable migration writes through the pinned CLI."""

import json
import os
import subprocess
from datetime import datetime
from pathlib import Path

from backlog_inventory import TEAM_ID, TEAM_KEY, WORKSPACE, description, identity

ISSUE_FIELDS = """id identifier url title description priority createdAt completedAt
state { name } team { id } parent { id } assignee { id } project { id }
cycle { id } estimate dueDate labels(first: 250) { nodes { id } pageInfo { hasNextPage } }
relations(first: 250) { nodes { id type relatedIssue { id } } pageInfo { hasNextPage } }"""


class LinearError(RuntimeError):
    pass


class Linear:
    def __init__(self, root, runner=subprocess.run):
        self.root = root
        self.runner = runner

    def call(self, document, variables=None):
        binary = self.root / "node_modules/.bin/linear"
        if not binary.is_file():
            raise LinearError("Pinned Linear CLI missing. Run mise exec -- npm ci.")
        result = self.runner(
            [
                str(binary),
                "--workspace",
                WORKSPACE,
                "--no-input",
                "api",
                document,
                "--variables-json",
                json.dumps(variables or {}),
            ],
            cwd=self.root,
            env={**os.environ, "LINEAR_IGNORE_ENV_FILE": "1"},
            text=True,
            capture_output=True,
            timeout=90,
        )
        if result.returncode:
            # Never echo credential-bearing subprocess arguments or response bodies.
            raise LinearError(
                f"Linear CLI failed (exit {result.returncode}); access or write outcome is incomplete. Re-run to reconcile stable IDs."
            )
        response = json.loads(result.stdout)
        if response.get("errors") or "data" not in response:
            raise LinearError("Linear returned GraphQL errors; no complete result.")
        return response["data"]

    def connection(self, document, key, variables=None):
        variables = dict(variables or {})
        result = []
        cursors = set()
        while True:
            page = self.call(document, variables)[key]
            result.extend(page["nodes"])
            info = page["pageInfo"]
            if not info["hasNextPage"]:
                return result
            cursor = info["endCursor"]
            if not cursor or cursor in cursors:
                raise LinearError("Linear pagination did not advance.")
            cursors.add(cursor)
            variables["after"] = cursor

    def issues(self):
        return self.connection(
            "query($after: String) { issues(first: 100, after: $after, includeArchived: true, "
            'filter: {team: {id: {eq: "'
            + TEAM_ID
            + '"}}}) { nodes { '
            + ISSUE_FIELDS
            + " } pageInfo { hasNextPage endCursor } } }",
            "issues",
        )

    def team(self):
        team = self.call(
            "query($id: String!) { team(id: $id) { id key triageEnabled autoClosePeriod autoArchivePeriod "
            "autoCloseParentIssues autoCloseChildIssues states { nodes { id name type } } } }",
            {"id": TEAM_ID},
        )["team"]
        if team["key"] != TEAM_KEY:
            raise LinearError("Destination team identity changed.")
        return team

    def labels(self):
        return self.connection(
            'query($after: String) { issueLabels(first: 100, after: $after, filter: {team: {id: {eq: "'
            + TEAM_ID
            + '"}}}) { nodes { id name isGroup parent { id name } } pageInfo { hasNextPage endCursor } } }',
            "issueLabels",
        )

    def views(self):
        return self.connection(
            "query($after: String) { customViews(first: 100, after: $after) { nodes { id name slugId "
            "filterData shared team { id } } pageInfo { hasNextPage endCursor } } }",
            "customViews",
        )

    def create(self, entity, input_type, fields, values):
        result = self.call(
            f"mutation($input: {input_type}!) {{ {entity}Create(input: $input) {{ success {entity} {{ {fields} }} }} }}",
            {"input": values},
        )[entity + "Create"]
        if not result["success"] or not result[entity]:
            raise LinearError(f"Linear did not confirm {entity} creation.")
        return result[entity]


def label_key(label):
    return (label["parent"]["name"] + "/" if label.get("parent") else "") + label[
        "name"
    ]


def view_definitions(manifest, label_ids):
    opened = {"state": {"type": {"nin": ["completed", "canceled", "duplicate"]}}}
    defs = {
        "open": ("Open Backlog", opened),
        "must-do": ("Must Do", {"and": [opened, {"priority": {"eq": 2}}]}),
        "completed": ("Completed History", {"state": {"type": {"eq": "completed"}}}),
    }
    for key, name, label in [
        ("quick-wins", "Quick Wins", "Effort category/quick-win"),
        ("needs-design", "Needs Design", "Effort category/needs-design"),
        ("exploratory", "Exploratory", "exploratory"),
        ("human", "Human Requests", "origin:human"),
    ]:
        defs[key] = (
            name,
            {"and": [opened, {"labels": {"some": {"id": {"eq": label_ids[label]}}}}]},
        )
    for area in sorted({entry["area"] for entry in manifest["entries"]}):
        defs["area:" + area] = (
            area + " — Open Work",
            {
                "and": [
                    opened,
                    {"labels": {"some": {"id": {"eq": label_ids["area:" + area]}}}},
                ]
            },
        )
    return {
        key: {
            "id": identity("view:" + key),
            "name": name,
            "teamId": TEAM_ID,
            "shared": True,
            "filterData": {"and": [{"team": {"id": {"eq": TEAM_ID}}}, filters]},
        }
        for key, (name, filters) in defs.items()
    }


def configure(client, manifest, save):
    team = client.team()
    states = {state["name"]: state["id"] for state in team["states"]["nodes"]}
    for name in ("Backlog", "Done"):
        if name not in states:
            raise LinearError(f"Required state missing: {name}")
    settings = {
        "triageEnabled": True,
        "autoClosePeriod": None,
        "autoArchivePeriod": 12,
        "autoCloseParentIssues": False,
        "autoCloseChildIssues": False,
    }
    if any(team[key] != value for key, value in settings.items()):
        result = client.call(
            "mutation($id: String!, $input: TeamUpdateInput!) { teamUpdate(id: $id, input: $input) { success } }",
            {"id": TEAM_ID, "input": settings},
        )
        if not result["teamUpdate"]["success"]:
            raise LinearError("Team configuration was not confirmed.")
        team = client.team()
        if any(team[key] != value for key, value in settings.items()):
            raise LinearError("Team configuration differs after update.")
    labels = {label_key(label): label for label in client.labels()}
    wanted = sorted(
        {label for entry in manifest["entries"] for label in entry["labels"]}
        | {
            "Effort category/quick-win",
            "Effort category/needs-design",
            "exploratory",
            "origin:human",
        }
    )
    for group in ("Type", "Effort category"):
        if group not in labels:
            labels[group] = client.create(
                "issueLabel",
                "IssueLabelCreateInput",
                "id name isGroup parent { id name }",
                {
                    "id": identity("label:" + group),
                    "name": group,
                    "teamId": TEAM_ID,
                    "isGroup": True,
                },
            )
        if not labels[group]["isGroup"]:
            raise LinearError(f"Existing {group} label is not a group.")
    for key in wanted:
        if key not in labels:
            values = {"id": identity("label:" + key), "name": key, "teamId": TEAM_ID}
            if "/" in key:
                group, name = key.split("/", 1)
                values.update(name=name, parentId=labels[group]["id"])
            labels[key] = client.create(
                "issueLabel",
                "IssueLabelCreateInput",
                "id name isGroup parent { id name }",
                values,
            )
    manifest["label_ids"] = {key: labels[key]["id"] for key in wanted}
    existing = {view["id"]: view for view in client.views()}
    definitions = view_definitions(manifest, manifest["label_ids"])
    manifest.setdefault("views", {})
    for key, values in definitions.items():
        view = existing.get(values["id"])
        if view is None:
            view = client.create(
                "customView",
                "CustomViewCreateInput",
                "id name slugId filterData shared team { id }",
                values,
            )
        if (
            view["name"] != values["name"]
            or view["filterData"] != values["filterData"]
            or not view["shared"]
            or view["team"]["id"] != TEAM_ID
        ):
            raise LinearError(f"Existing view differs: {key}")
        manifest["views"][key] = {
            "id": view["id"],
            "url": f"https://linear.app/{WORKSPACE}/view/{view['slugId']}",
        }
    save()
    return states


def same_date(left, right):
    return datetime.fromisoformat(
        left.replace("Z", "+00:00")
    ) == datetime.fromisoformat(right.replace("Z", "+00:00"))


def same_markdown(expected, actual):
    if expected == actual:
        return True
    result = subprocess.run(
        ["node", str(Path(__file__).with_name("backlog_markdown.mjs"))],
        input=json.dumps([expected, actual]),
        text=True,
        capture_output=True,
        timeout=30,
    )
    if result.returncode or result.stdout.strip() not in ("equal", "different"):
        raise LinearError(
            "Markdown comparison failed; cannot verify description fidelity."
        )
    return result.stdout.strip() == "equal"


def verify_issue(entry, issue, manifest):
    expected = {
        "title": entry["title"],
        "description": description(entry, manifest),
        "priority": entry["priority"],
    }
    for key, value in expected.items():
        if not (
            same_markdown(value, issue[key])
            if key == "description"
            else issue[key] == value
        ):
            raise LinearError(
                f"{entry['source_key']}: {key} differs; preserve remote edits and reconcile manually."
            )
    if issue["team"]["id"] != TEAM_ID or issue["state"]["name"] != entry["state"]:
        raise LinearError(f"{entry['source_key']}: team/state differs.")
    if (issue["parent"] or {}).get("id") != entry["parent_id"]:
        raise LinearError(f"{entry['source_key']}: parent differs.")
    if (
        issue["labels"]["pageInfo"]["hasNextPage"]
        or issue["relations"]["pageInfo"]["hasNextPage"]
    ):
        raise LinearError("Issue label/relation selection is incomplete.")
    if {label["id"] for label in issue["labels"]["nodes"]} != {
        manifest["label_ids"][label] for label in entry["labels"]
    }:
        raise LinearError(f"{entry['source_key']}: labels differ.")
    for key, value in {
        **(
            {"createdAt": entry["estimated_created_at"]}
            if entry.get("estimated_created_at")
            else {}
        ),
        **entry["dates"],
    }.items():
        if not issue[key] or not same_date(issue[key], value):
            raise LinearError(f"{entry['source_key']}: historical {key} differs.")
    for key in ("assignee", "project", "cycle", "estimate", "dueDate"):
        if issue[key] is not None:
            raise LinearError(f"{entry['source_key']}: unexpected {key}.")


def apply(client, manifest, save, limit=None):
    states = configure(client, manifest, save)
    remote = {issue["id"]: issue for issue in client.issues()}
    entries = manifest["entries"][:limit] if limit else manifest["entries"]
    for entry in entries:
        issue = remote.get(entry["id"])
        if issue is None:
            values = {
                "id": entry["id"],
                "teamId": TEAM_ID,
                "title": entry["title"],
                "description": description(entry, manifest),
                "priority": entry["priority"],
                "stateId": states[entry["state"]],
                "labelIds": [manifest["label_ids"][label] for label in entry["labels"]],
                "useDefaultTemplate": False,
                **entry["dates"],
            }
            if entry.get("estimated_created_at"):
                values["createdAt"] = entry["estimated_created_at"]
            if entry["parent_id"]:
                values["parentId"] = entry["parent_id"]
            issue = client.create("issue", "IssueCreateInput", ISSUE_FIELDS, values)
            remote[entry["id"]] = issue
        verify_issue(entry, issue, manifest)
        entry.update(identifier=issue["identifier"], url=issue["url"])
        save()
        print(f"Reconciled {issue['identifier']}: {entry['title']}", flush=True)
    for entry in entries:
        for blocker in entry["blocked_by"]:
            relation_id = identity("blocks:" + blocker + ":" + entry["id"])
            relations = remote[blocker]["relations"]["nodes"]
            matches = [
                relation
                for relation in relations
                if relation["type"] == "blocks"
                and relation["relatedIssue"]["id"] == entry["id"]
            ]
            if not matches:
                relation = client.create(
                    "issueRelation",
                    "IssueRelationCreateInput",
                    "id type relatedIssue { id }",
                    {
                        "id": relation_id,
                        "type": "blocks",
                        "issueId": blocker,
                        "relatedIssueId": entry["id"],
                    },
                )
                relations.append(relation)
    save()


def verify(client, manifest, limit=None):
    team = client.team()
    if (
        not team["triageEnabled"]
        or team["autoClosePeriod"]
        or team["autoArchivePeriod"] != 12
        or team["autoCloseParentIssues"]
        or team["autoCloseChildIssues"]
    ):
        raise LinearError("Team retention/intake configuration differs.")
    remote = {issue["id"]: issue for issue in client.issues()}
    entries = manifest["entries"][:limit] if limit else manifest["entries"]
    for entry in entries:
        if entry["id"] not in remote:
            raise LinearError(f"Missing issue: {entry['source_key']}")
        issue = remote[entry["id"]]
        verify_issue(entry, issue, manifest)
        if issue["identifier"] != entry["identifier"] or issue["url"] != entry["url"]:
            raise LinearError("Manifest issue mapping differs.")
        for blocker in entry["blocked_by"]:
            if not any(
                relation["type"] == "blocks"
                and relation["relatedIssue"]["id"] == entry["id"]
                for relation in remote[blocker]["relations"]["nodes"]
            ):
                raise LinearError("Missing blocking relation.")
    views = {view["id"]: view for view in client.views()}
    for key, expected in view_definitions(manifest, manifest["label_ids"]).items():
        view = views.get(expected["id"])
        if (
            not view
            or view["filterData"] != expected["filterData"]
            or not view["shared"]
        ):
            raise LinearError(f"Missing or changed view: {key}")
    return len(entries)
