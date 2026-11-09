"""Lossless entry inventory for the one-time Markdown-to-Linear migration."""

import hashlib
import posixpath
import re
import uuid
from datetime import date, timedelta
from urllib.parse import quote, urlsplit

TEAM_ID = "58134eca-7005-4b28-bffc-3243ca696a1e"
TEAM_KEY = "STU"
WORKSPACE = "kve"
REPOSITORY_URL = "https://github.com/kyleve/Stuff"
NAMESPACE = uuid.UUID("92e92f26-8725-4a2a-9c59-427287d39a18")
TYPE = r"feat|fix|refactor|perf|test|docs|design|convention|localization"
PREFIX = re.compile(
    rf"^(?P<type>{TYPE})(?:\((?P<scope>[^)]+)\))?(?:\s+\[(?P<effort>[^]]+)\])?:\s*"
)
BULLET = re.compile(r"^(?P<indent>[ \t]*)- (?P<body>.*)")
HEADING = re.compile(r"^#{1,6} (.+)")
PRIORITIES = {"PX": 0, "P0": 2, "P1": 3, "P2": 4, None: 0}


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def identity(key):
    # Linear validates client IDs as UUIDv4. Keep deterministic bytes for retry identity.
    return str(uuid.UUID(bytes=uuid.uuid5(NAMESPACE, key).bytes, version=4))


def concise_title(body):
    text = PREFIX.sub("", " ".join(body.split()))
    text = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"[`*]", "", text)
    if text.startswith(("broken-snapshots —", "TLA+ —")):
        text = text.replace(" — ", ": ", 1)
    text = re.split(r" — |\. (?=[A-Z])|\n", text)[0].strip()
    if len(text) > 160:
        text = text[:157].rsplit(" ", 1)[0] + "…"
    return text


def historical_dates(body, state):
    """Only explicit creation/closure dates qualify; audit dates never do."""
    result = {}
    patterns = {"createdAt": r"\bcreated(?: on)?[: ]+(\d{4}-\d{2}-\d{2})"}
    if state == "Done":
        patterns["completedAt"] = (
            r"\b(?:closed|resolved)(?: on)?[: ]+(\d{4}-\d{2}-\d{2})"
        )
    for field, pattern in patterns.items():
        dates = set(re.findall(pattern, body, re.I))
        if len(dates) == 1:
            value = dates.pop()
            date.fromisoformat(value)
            result[field] = value + "T00:00:00Z"
    return result


def estimate_creation_dates(entries):
    """User-approved estimates allow Linear to preserve known completion dates."""
    for entry in entries:
        if "completedAt" not in entry["dates"] or "createdAt" in entry["dates"]:
            continue
        completed = date.fromisoformat(entry["dates"]["completedAt"][:10])
        origins = [
            date.fromisoformat(value)
            for value in re.findall(
                r"\((?:human|audit|agent)\s+(\d{4}-\d{2}-\d{2})", entry["body"], re.I
            )
        ]
        prior = [value for value in origins if value < completed]
        estimated = min(prior) if prior else completed - timedelta(days=1)
        entry["estimated_created_at"] = estimated.isoformat() + "T00:00:00Z"
        entry["creation_date_basis"] = (
            "Earliest recorded origin date before completion"
            if prior
            else "One day before recorded completion; no earlier origin date is available"
        )


def labels_for(body, area, bucket):
    labels = {"area:" + area}
    prefix = PREFIX.match(body)
    if prefix:
        labels.add("Type/" + prefix["type"])
        if prefix["effort"]:
            labels.add("Effort category/" + prefix["effort"])
        scopes = (prefix["scope"] or "").split(",")
        labels.update("module:" + scope.strip() for scope in scopes if scope.strip())
    if not any(label.startswith("module:") for label in labels) and area not in (
        "Repo",
        "Where",
    ):
        labels.add("module:" + area)
    if bucket == "PX":
        labels.add("exploratory")
    for origin, pattern in {
        "human": r"\(human\b",
        "audit": r"\(audit\b",
        "review": r"\(pr[# ]|\(agent review|\(From .*review",
        "agent": r"\(agent\b",
    }.items():
        if re.search(pattern, body, re.I):
            labels.add("origin:" + origin)
    return sorted(labels)


def parse_file(path, source, revision, split_nested=()):
    """Preserve parents intact; split only typed or explicitly reviewed child tasks."""
    lines = source.splitlines(keepends=True)
    area = "Repo" if path == "TODOs.md" else path.split("/")[-2]
    state = None
    bucket = None
    headings = []
    candidates = []
    structural = []
    context = []
    for index, line in enumerate(lines):
        heading = HEADING.match(line)
        if heading:
            title = heading[1]
            if title in ("Open issues", "Completed issues"):
                state = "Backlog" if title == "Open issues" else "Done"
                bucket = None
                headings = [title]
            elif state:
                headings = headings[:1] + [title]
                priority = re.match(r"(P[X012])(?:s|\b)", title)
                # Non-priority subsections inherit the enclosing priority.
                if priority:
                    bucket = priority[1]
            structural.append(index + 1)
            context = []
            continue
        if not state:
            structural.append(index + 1)
            continue
        bullet = BULLET.match(line)
        if bullet:
            indent = len(bullet["indent"].expandtabs(4))
            if indent == 0 or PREFIX.match(bullet["body"]) or index + 1 in split_nested:
                candidates.append(
                    {
                        "start": index,
                        "indent": indent,
                        "state": state,
                        "bucket": bucket,
                        "headings": list(headings),
                        "context": "".join(context),
                    }
                )
                continue
        if not candidates or (headings != candidates[-1]["headings"]):
            context.append(line)
    entries = []
    covered = set(structural)
    for candidate in candidates:
        start = candidate["start"]
        end = len(lines)
        for index in range(start + 1, len(lines)):
            bullet = BULLET.match(lines[index])
            if HEADING.match(lines[index]) or (
                bullet and len(bullet["indent"].expandtabs(4)) <= candidate["indent"]
            ):
                end = index
                break
        raw = "".join(lines[start:end])
        body = re.sub(r"^[ \t]*- ", "", raw, count=1).rstrip()
        key = f"{revision}:{path}:{start + 1}"
        parents = [
            entry
            for entry in entries
            if entry["start_line"] < start + 1 <= entry["end_line"]
            and entry["indent"] < candidate["indent"]
        ]
        parent = parents[-1] if parents else None
        if candidate["indent"] and parent is None:
            raise ValueError(f"Orphan child at {path}:{start + 1}")
        entry = {
            "id": identity(key),
            "source_key": key,
            "path": path,
            "start_line": start + 1,
            "end_line": end,
            "indent": candidate["indent"],
            "source_sha256": digest(raw),
            "body": body,
            "context": candidate["context"].strip(),
            "headings": candidate["headings"],
            "area": area,
            "bucket": candidate["bucket"],
            "state": candidate["state"],
            "title": concise_title(body),
            "priority": PRIORITIES[candidate["bucket"]],
            "labels": labels_for(body, area, candidate["bucket"]),
            "dates": historical_dates(body, candidate["state"]),
            "parent_id": parent["id"] if parent else None,
            "blocked_by": [],
            "identifier": None,
            "url": None,
        }
        # The repository contract states that nested tasks depend on their parent.
        if parent and PREFIX.match(BULLET.match(lines[start])["body"]):
            entry["blocked_by"] = [parent["id"]]
        entries.append(entry)
        covered.update(range(start + 1, end + 1))
    # Section prose belongs to every following entry in that section, not a new issue.
    for index, line in enumerate(lines, 1):
        if index not in covered and line.strip():
            if any(line.strip() in entry["context"] for entry in entries):
                covered.add(index)
            else:
                raise ValueError(
                    f"Unclassified source at {path}:{index}: {line.strip()[:100]}"
                )
    return entries


def resolve_links(text, path, revision, manifest):
    def replace(match):
        label, target = match.groups()
        if urlsplit(target).scheme or target.startswith("//"):
            return match[0]
        split = urlsplit(target)
        destination = (
            posixpath.normpath(posixpath.join(posixpath.dirname(path), split.path))
            if split.path
            else path
        )
        if destination.endswith("TODOs.md") and not split.fragment:
            view = manifest.get("views", {}).get(
                "area:"
                + ("Repo" if destination == "TODOs.md" else destination.split("/")[-2])
            )
            if view:
                return f"[{label}]({view['url']})"
        suffix = "#" + split.fragment if split.fragment else ""
        return (
            f"[{label}]({REPOSITORY_URL}/blob/{revision}/{quote(destination)}{suffix})"
        )

    return re.sub(r"\[([^]\n]+)\]\(([^)\s]+)\)", replace, text)


def description(entry, manifest):
    revision = manifest["source_revision"]
    source_url = f"{REPOSITORY_URL}/blob/{revision}/{quote(entry['path'])}#L{entry['start_line']}-L{entry['end_line']}"
    context = (entry["context"] + "\n\n") if entry["context"] else ""
    text = resolve_links(context + entry["body"], entry["path"], revision, manifest)
    dates = "; ".join(f"{key}: {value}" for key, value in entry["dates"].items())
    unknown = [
        name for name in ("createdAt", "completedAt") if name not in entry["dates"]
    ]
    if entry["state"] != "Done":
        unknown = [name for name in unknown if name != "completedAt"]
    provenance = [
        "## Migration provenance",
        f"[Original entry]({source_url})",
        "Original section: " + " / ".join(entry["headings"]),
        f"Original priority bucket: {entry['bucket'] or 'not recorded'}.",
        f"Migration key: `{entry['source_key']}`.",
        "Imported as recorded; migration is not a fresh verification.",
    ]
    if dates:
        provenance += [
            dates,
            "Date-only historical values use midnight UTC; no original time of day was recorded.",
        ]
    if entry.get("estimated_created_at"):
        provenance.append(
            f"Estimated creation date: {entry['estimated_created_at']}. {entry['creation_date_basis']}. This is an import estimate, not a verified historical creation date."
        )
        unknown = [name for name in unknown if name != "createdAt"]
    if unknown:
        provenance.append(
            "Historical "
            + ", ".join(unknown)
            + " unknown; native timestamps reflect import where Linear supplies them."
        )
    return text + "\n\n" + "\n\n".join(provenance)
