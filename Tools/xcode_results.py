"""Shared models and traversal for ``xcresulttool ... tests`` JSON.

The public shell commands remain responsible for invoking ``xcresulttool``.
This module owns the schema-tolerant tree walk used by their reports.
"""

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Iterable, Iterator, Mapping, Sequence, Tuple


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

    for node in document.get("testNodes", []):
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
        try:
            duration = float(node.get("durationInSeconds") or 0)
        except (TypeError, ValueError):
            duration = 0.0
        yield TestCase(
            bundle=bundle,
            suites=suites,
            name=name or "?",
            node_identifier=str(node.get("nodeIdentifier") or ""),
            result=str(node.get("result") or "").lower(),
            duration_seconds=duration,
        )

    children = node.get("children", [])
    if isinstance(children, Sequence) and not isinstance(children, (str, bytes)):
        for child in children:
            if isinstance(child, Mapping):
                yield from _walk(child, bundle=bundle, suites=suites)
