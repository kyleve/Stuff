"""Shared models and traversal for ``xcresulttool ... tests`` JSON.

The public shell commands remain responsible for invoking ``xcresulttool``.
This module owns the schema-tolerant tree walk used by their reports.
"""

from dataclasses import dataclass
import json
import math
from pathlib import Path
import re
from typing import Iterable, Iterator, Mapping, Sequence, Tuple


DURATION_COMPONENT = re.compile(r"(?P<value>\d+(?:\.\d+)?)\s*(?P<unit>ms|h|m|s)")
SECONDS_PER_UNIT = {"ms": 0.001, "s": 1.0, "m": 60.0, "h": 3600.0}


def test_duration(node: Mapping[str, object]) -> float:
    """Sum executed arguments/repetitions; Xcode's parent duration is a mean.

    Keep one logical test identity for reports and reruns. Prefer precise
    numeric seconds over the rounded display string on each execution leaf.
    """
    if str(node.get("result", "")).lower() == "skipped":
        return 0.0
    executions = [
        child
        for child in _children(node)
        if child.get("nodeType") in ("Arguments", "Repetition")
    ]
    if executions:
        return sum(test_duration(child) for child in executions)
    for key in ("durationInSeconds", "duration"):
        value = node.get(key)
        if value is None or isinstance(value, bool):
            continue
        try:
            seconds = float(value)
        except (TypeError, ValueError):
            if key != "duration":
                continue
            text = str(value).strip()
            components = list(DURATION_COMPONENT.finditer(text))
            if not components or DURATION_COMPONENT.sub("", text).strip():
                continue
            seconds = sum(
                float(part.group("value")) * SECONDS_PER_UNIT[part.group("unit")]
                for part in components
            )
        if math.isfinite(seconds) and seconds >= 0:
            return seconds
    return 0.0


def _children(node: Mapping[str, object]) -> Iterator[Mapping[str, object]]:
    children = node.get("children", [])
    if isinstance(children, Sequence) and not isinstance(children, (str, bytes)):
        yield from (child for child in children if isinstance(child, Mapping))


@dataclass(frozen=True)
class TestCase:
    """One test-case node with the bundle and suite ancestry needed by reports."""

    bundle: str
    suites: Tuple[str, ...]
    name: str
    node_identifier: str
    result: str
    duration_seconds: float

    @property
    def suite_name(self) -> str:
        return self.suites[-1] if self.suites else "?"

    @property
    def display_identifier(self) -> str:
        return "/".join((self.bundle, self.suite_name, self.name))

    @property
    def suite_identifier(self) -> str:
        return "/".join((self.bundle, self.suite_name))

    @property
    def only_testing_identifier(self) -> str:
        identifier = self.node_identifier
        if not identifier:
            identifier = "/".join((*self.suites, self.name))
        if self.bundle in ("", "?") or identifier.startswith(self.bundle + "/"):
            return identifier
        return f"{self.bundle}/{identifier}"


def test_cases(document: Mapping[str, object]) -> Iterator[TestCase]:
    """Yield every test case in document order, tolerating unknown node kinds."""

    if not isinstance(document, Mapping):
        return
    nodes = document.get("testNodes", [])
    if not isinstance(nodes, Sequence) or isinstance(nodes, (str, bytes)):
        return
    for node in nodes:
        if isinstance(node, Mapping):
            yield from _walk(node, bundle="?", suites=())


def load_test_cases(paths: Iterable[Path]) -> Iterator[TestCase]:
    for path in paths:
        with path.open() as stream:
            document = json.load(stream)
        yield from test_cases(document)


def _walk(
    node: Mapping[str, object],
    bundle: str,
    suites: Tuple[str, ...],
) -> Iterator[TestCase]:
    node_type = str(node.get("nodeType") or "")
    name = str(node.get("name") or "")
    if node_type == "Unit test bundle":
        bundle = name or bundle
    elif node_type == "Test Suite":
        suites = (*suites, name)
    elif node_type == "Test Case":
        yield TestCase(
            bundle=bundle,
            suites=suites,
            name=name or "?",
            node_identifier=str(node.get("nodeIdentifier") or ""),
            result=str(node.get("result") or "").lower(),
            duration_seconds=test_duration(node),
        )

    for child in _children(node):
        yield from _walk(child, bundle=bundle, suites=suites)
