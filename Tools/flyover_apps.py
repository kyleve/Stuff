"""Trusted registrations for native Flyover capture adapters."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import re

from Tools.repository import repository_root


@dataclass(frozen=True)
class FlyoverApp:
    app_id: str
    title: str
    test_identifier: str


def load_apps(path: Path | None = None) -> tuple[FlyoverApp, ...]:
    source = (
        path
        if path is not None
        else repository_root(__file__) / ".github/flyover-apps.json"
    )
    rows = json.loads(source.read_text())
    if not isinstance(rows, list) or not rows:
        raise ValueError("Flyover requires at least one registered app")
    apps = []
    for row in rows:
        if not isinstance(row, dict) or set(row) != {"id", "title", "testIdentifier"}:
            raise ValueError("Invalid Flyover app registration")
        if (
            not isinstance(row["id"], str)
            or not re.fullmatch(r"[a-z][a-z0-9-]*", row["id"])
            or not isinstance(row["title"], str)
            or not row["title"].strip()
            or not isinstance(row["testIdentifier"], str)
            or not re.fullmatch(
                r"[A-Za-z][A-Za-z0-9_]*/[A-Za-z][A-Za-z0-9_]*/[A-Za-z][A-Za-z0-9_]*\(\)",
                row["testIdentifier"],
            )
        ):
            raise ValueError("Invalid Flyover app identity or capture test")
        apps.append(FlyoverApp(row["id"], row["title"], row["testIdentifier"]))
    if len({app.app_id for app in apps}) != len(apps):
        raise ValueError("Duplicate Flyover app identity")
    return tuple(apps)


def load_app(app_id: str) -> FlyoverApp:
    for app in load_apps():
        if app.app_id == app_id:
            return app
    raise ValueError(f"Unknown Flyover app: {app_id}")
