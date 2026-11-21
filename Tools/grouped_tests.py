"""Logical test modules compiled into the grouped iOS test bundle."""

from dataclasses import dataclass
import json
from pathlib import Path
import re
from typing import Optional
import subprocess


GROUPED_BUNDLE = "GroupedLibraryTests"


@dataclass
class GroupedTestSuites:
    bundles: set[str]
    owners: dict[str, str]

    @classmethod
    def from_repository(cls, root: Path) -> "GroupedTestSuites":
        from test_runner import _declarations

        project = (root / "Project.swift").read_text()
        names = re.search(
            r"let groupedLibraryTestNames: Set<String> = \[(.*?)\]", project, re.S
        )
        if not names:
            raise ValueError("Project.swift has no groupedLibraryTestNames declaration")
        members = set(re.findall(r'"(\w+)"', names[1]))
        declarations = _declarations(project)
        paths = {}
        for name in sorted(members):
            sources = re.search(r"sources:\s*\[([^\]]*)\]", declarations[name])
            if not sources:
                raise ValueError(f"no literal test sources for {name}")
            paths[name] = [
                str(path)
                for glob in re.findall(r'"([^"]+)"', sources[1])
                for path in sorted(
                    root.glob(glob + "/*.swift" if glob.endswith("/**") else glob)
                )
                if path.suffix == ".swift"
            ]
            if not paths[name]:
                raise ValueError(f"no Swift test files found for {name}")

        swift = Path(
            subprocess.check_output(["xcrun", "--find", "swift"], text=True).strip()
        )
        host_modules = swift.parents[1] / "lib/swift/host"
        scanner = Path(__file__).with_name("GroupedTestSuites.swift")
        parsed = subprocess.run(
            [
                str(swift),
                "-I",
                str(host_modules),
                "-L",
                str(host_modules),
                str(scanner),
            ],
            input=json.dumps(paths),
            stdout=subprocess.PIPE,
            text=True,
            check=True,
        )
        owners = {}
        for name, suites in json.loads(parsed.stdout).items():
            for suite in suites:
                if suite in owners:
                    raise ValueError(
                        f"{suite} belongs to both {owners[suite]} and {name}"
                    )
                owners[suite] = name
        return cls(members, owners)

    @classmethod
    def from_manifest_or_repository(
        cls, root: Path, manifest_path: Optional[Path] = None
    ) -> "GroupedTestSuites":
        if manifest_path is not None and manifest_path.is_file():
            manifest = json.loads(manifest_path.read_text())
            if "groupedSuiteOwners" in manifest:
                owners = manifest["groupedSuiteOwners"]
                if (
                    not isinstance(owners, dict)
                    or not owners
                    or not all(
                        isinstance(suite, str)
                        and suite
                        and isinstance(bundle, str)
                        and bundle
                        for suite, bundle in owners.items()
                    )
                ):
                    raise ValueError(f"invalid groupedSuiteOwners in {manifest_path}")
                return cls(set(owners.values()), owners)
        return cls.from_repository(root)

    def logical_bundle(self, identifier: str) -> str:
        """Resolve an Xcode case or suite identifier independently of its display name."""
        outer = (
            identifier.removeprefix(GROUPED_BUNDLE + "/")
            .split("/", 1)[0]
            .split(".", 1)[0]
        )
        if outer not in self.owners:
            raise ValueError(
                f"no logical test module for {GROUPED_BUNDLE}/{identifier}"
            )
        return self.owners[outer]
