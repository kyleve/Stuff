import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from Tools.Tests.test_xcode_command_contracts import XcodeCommandFixture

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_selection import Graph


def manifests():
    package = {
        "products": [{"name": "PublicCore", "targets": ["Core"]}],
        "targets": [
            {"name": "Core", "path": "Shared/Core/Sources", "dependencies": []},
            {
                "name": "UI",
                "path": "Shared/UI/Sources",
                "dependencies": [{"target": ["Core"]}],
            },
            {
                "name": "MacrosTests",
                "type": "test",
                "path": "Macros/Tests",
                "dependencies": [{"byName": ["Core"]}],
            },
        ],
    }
    package["products"].append({"name": "UI", "targets": ["UI"]})
    project = """
func unitTests() -> Target {
    var dependencies: [TargetDependency] = [
        .package(product: productDependency),
        .target(name: "Host"),
    ]
    for product in extraPackageProducts {
        dependencies.append(.package(product: product))
    }
    return .target(name: name, dependencies: dependencies)
}
let project = Project(
    targets: addingGroupedLibraryTests(to: [
        .target(
            name: "Host",
            product: .app,
            sources: ["Host/Sources/**"],
            resources: ["Host/Resources/**"],
            dependencies: [.target(name: "Extension")],
        ),
        .target(
            name: "Extension",
            product: .appExtension,
            sources: ["Extension/Sources/**"],
            dependencies: [],
        ),
"""
    for name, source, product, extra in [
        (
            "CoreTests",
            "Shared/Core/Tests/**/*.swift",
            "PublicCore",
            'resources: [.folderReference(path: "Shared/Core/Tests/Fixtures")],',
        ),
        ("UITests", "Shared/UI/Tests/**", "UI", ""),
        ("UISnapshotTests", "Shared/UI/SnapshotTests/**", "UI", ""),
        ("ToolsSnapshotTests", "Tools/SnapshotTests/**", "External", ""),
    ] + [(f"Other{i}Tests", f"Other/{i}/Tests/**", "External", "") for i in range(11)]:
        sources = json.dumps(source)
        if name == "UISnapshotTests":
            sources += ',\n                "Shared/UI/Tests/Support/TestStore.swift"'
        project += f'''        unitTests(
            name: "{name}",
            productDependency: "{product}",
            sources: [{sources}],
            {extra}
        ),
'''
    return package, project + "    ]),\n)"


class SelectionPolicyTests(unittest.TestCase):
    def setUp(self):
        self.package, self.project = manifests()
        self.graph = Graph.read(self.package, self.project)

    def test_shared_multiline_sources_include_every_owner(self):
        report = self.graph.select(["Shared/UI/Tests/Support/TestStore.swift"])
        self.assertEqual(["UISnapshotTests", "UITests"], report["selected"])
        self.assertEqual(13, len(report["skipped"]))

    def test_literal_resource_directory_and_double_star_extension(self):
        for path in (
            "Shared/Core/Tests/Nested/Test.swift",
            "Shared/Core/Tests/Fixtures/a flight.json",
        ):
            self.assertEqual(["CoreTests"], self.graph.select([path])["selected"])

    def test_product_alias_reverse_dependencies_and_host_tests(self):
        report = self.graph.select(["Shared/Core/Sources/Value.swift"])
        self.assertEqual(
            ["CoreTests", "UISnapshotTests", "UITests"], report["selected"]
        )
        self.assertEqual(["MacrosTests"], report["host_tests"])

    def test_implicit_host_and_transitive_host_extensions(self):
        for path in (
            "Host/Sources/Main.swift",
            "Host/Resources/icon.png",
            "Extension/Sources/Extension.swift",
        ):
            self.assertEqual(15, len(self.graph.select([path])["selected"]))

    def test_generated_site_inputs_and_unknown_tooling(self):
        for path in (
            "Tools/InstallerKit/Site/src/components/EmptyState.astro",
            "Tools/InstallerKit/installer_update_site.py",
            "Tools/Tests/Fixtures/installer_update_fixtures.py",
            "Tools/Tests/Fixtures/installer_update_site_snapshots.py",
            "package-lock.json",
        ):
            self.assertEqual(
                ["ToolsSnapshotTests"], self.graph.select([path])["selected"]
            )
        for path in (
            "Tools/test_runner.py",
            ".circleci/continue.yml",
            "unknown.swift",
            "Project.swift",
            "Tools/InstallerKit/stamp-installer-info.sh",
        ):
            report = self.graph.select([path])
            self.assertEqual("full", report["mode"])
            self.assertEqual([], report["skipped"])
            self.assertEqual(["MacrosTests"], report["host_tests"])

    def test_qualified_helper_return_type_preserves_host_dependencies(self):
        graph = Graph.read(
            self.package,
            self.project.replace("-> Target", "-> ProjectDescription.Target"),
        )
        self.assertEqual(15, len(graph.select(["Host/Sources/Main.swift"])["selected"]))

    def test_empty_docs_and_unknown_rendered_markdown(self):
        self.assertEqual("empty", self.graph.select([])["mode"])
        self.assertEqual(
            "empty", self.graph.select(["Plans/example/README.md"])["mode"]
        )
        self.assertEqual(
            "full", self.graph.select(["NewApp/Resources/content.md"])["mode"]
        )

    def test_overlapping_source_roots_are_not_first_match_wins(self):
        self.package["targets"].append(
            {"name": "Nested", "path": "Shared/Core/Sources/Nested", "dependencies": []}
        )
        self.package["products"].append({"name": "External", "targets": ["Nested"]})
        graph = Graph.read(self.package, self.project)
        report = graph.select(["Shared/Core/Sources/Nested/Value.swift"])
        self.assertEqual(15, len(report["selected"]))

    def test_unsupported_sources_resources_dependencies_and_target_lists_fail(self):
        changes = [
            ("-> Target", "-> UnknownTarget"),
            ('productDependency: "PublicCore"', 'productDependency: "Public" + "Core"'),
            (
                "func unitTests()",
                'func unitTests(extraPackageProducts: [String] = ["PublicCore"])',
            ),
            (
                "func unitTests()",
                'func unitTests(resources: ResourceFileElements = ["Shared/Fixtures/**"])',
            ),
            (
                "dependencies: dependencies)",
                "dependencies: dependencies + otherDependencies)",
            ),
            ('sources: ["Shared/UI/Tests/**"]', "sources: computedSources"),
            (
                'sources: ["Shared/UI/Tests/**"]',
                'sources: ["Shared/UI/Tests/**"] + otherSources',
            ),
            (
                'resources: [.folderReference(path: "Shared/Core/Tests/Fixtures")]',
                "resources: computedResources",
            ),
            ("dependencies: []", "dependencies: [.target(name: computedName)]"),
            ('name: "Extension"', "name: computedName"),
            (
                "for product in extraPackageProducts",
                "dependencies += moreDependencies\n    for product in extraPackageProducts",
            ),
        ]
        for before, after in changes:
            with self.subTest(after=after), self.assertRaises(ValueError):
                Graph.read(self.package, self.project.replace(before, after))


class SelectionCommandTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.fixture = XcodeCommandFixture(self.temporary.name)
        self.root = self.fixture.root
        self.git_binary = shutil.which("git")
        (self.fixture.bin / "git").unlink()
        (self.fixture.bin / "git").symlink_to(self.git_binary)
        package, project = manifests()
        (self.root / "Project.swift").write_text(project)
        (self.root / "package-fixture.json").write_text(json.dumps(package))
        self.fixture._write_executable(
            self.fixture.bin / "swift",
            """#!/bin/bash
printf 'swift %s\\n' "$*" >>"$TOOL_LOG"
if [ "${PACKAGE_STATUS:-0}" != 0 ]; then exit "$PACKAGE_STATUS"; fi
cat package-fixture.json
""",
        )
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        (self.root / ".gitignore").write_text(
            "home/\ncommands.log\n*.xcresult/\ntest work/\ntemporary files/\nTools/__pycache__/\n"
        )
        self.write("Shared/UI/Tests/Support/TestStore.swift", "old")
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        self.git("branch", "base")

    def git(self, *arguments):
        return subprocess.run(
            [self.git_binary, *arguments],
            cwd=self.root,
            capture_output=True,
            text=True,
            env={
                **os.environ,
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull,
            },
            check=True,
        ).stdout.strip()

    def write(self, relative, contents):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents)

    def preview(self, *arguments):
        result = self.fixture.run(
            "test", "--dry-run", "--json", "--base", "base", *arguments
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertFalse(self.fixture.test_work.exists())
        self.assertNotIn("xcodebuild", self.fixture.command_log())
        self.assertNotIn("mise ", self.fixture.command_log())
        self.assertNotIn("xcrun", self.fixture.command_log())
        return json.loads(result.stdout)

    def test_preview_and_execution_use_same_bundle_selection(self):
        self.write("Shared/UI/Tests/Support/TestStore.swift", "changed")
        report = self.preview()
        self.assertEqual(["UISnapshotTests", "UITests"], report["selected"])
        self.assertEqual(
            "", self.fixture.run("test", "--dry-run", "--base", "base").stderr
        )
        result = self.fixture.run(
            "test",
            "--base",
            "base",
            "--no-generate",
            "--skip-architecture",
            "--skip-host-tests",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        commands = self.fixture.command_log()
        for name in report["selected"]:
            self.assertIn("-only-testing:" + name, commands)
        self.assertNotIn("-only-testing:CoreTests", commands)

    def test_rename_deletion_newline_and_untracked_paths(self):
        old = "Shared/UI/Tests/Support/TestStore.swift"
        new = "Shared/Core/Tests/name with spaces ü\nTest.swift"
        (self.root / new).parent.mkdir(parents=True, exist_ok=True)
        self.git("mv", old, new)
        self.write("Shared/UI/Tests/New.swift", "new")
        report = self.preview()
        self.assertEqual(
            ["CoreTests", "UISnapshotTests", "UITests"], report["selected"]
        )
        self.assertIn(old, report["changed_paths"])
        self.assertIn(new, report["changed_paths"])
        self.assertIn("Shared/UI/Tests/New.swift", report["changed_paths"])

    def test_head_replay_excludes_dirty_and_untracked_files(self):
        self.write("Shared/Core/Tests/Test.swift", "new")
        self.git("add", "Shared/Core")
        self.git("commit", "-qm", "feature")
        self.write("unknown.swift", "dirty")
        report = self.preview("--head", "HEAD")
        self.assertEqual(["CoreTests"], report["selected"])
        self.assertFalse(report["comparison"]["includes_local_changes"])
        self.assertNotIn("unknown.swift", report["changed_paths"])

    def test_missing_history_falls_back_to_all_bundles(self):
        report = self.preview("--base", "missing-branch")
        self.assertEqual("full", report["mode"])
        self.assertEqual([], report["skipped"])
        self.assertIn("Git comparison unavailable", report["fallback_reason"])
        result = self.fixture.run(
            "test",
            "--base",
            "missing-branch",
            "--no-generate",
            "--skip-architecture",
            "--skip-host-tests",
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertIn("-scheme Stuff-iOS-FullTests", self.fixture.command_log())
        self.assertIn("-scheme StuffSnapshotTests", self.fixture.command_log())
        self.assertNotIn("-only-testing:", self.fixture.command_log())

    def test_complete_merge_base_includes_earlier_feature_commits(self):
        self.write("Shared/Core/Tests/First.swift", "first")
        self.git("add", "Shared/Core")
        self.git("commit", "-qm", "first feature commit")
        self.write("Shared/UI/Tests/Last.swift", "last")
        self.git("add", "Shared/UI")
        self.git("commit", "-qm", "last feature commit")
        head = self.git("rev-parse", "HEAD")
        self.git("checkout", "-q", "base")
        self.write("Host/Sources/Main.swift", "main advance")
        self.git("add", "Host")
        self.git("commit", "-qm", "base advance")
        report = self.preview("--head", head)
        self.assertEqual(["CoreTests", "UITests"], report["selected"])
        self.assertNotIn("Host/Sources/Main.swift", report["changed_paths"])

    def test_bad_flags_and_manifest_failure_do_not_launch_builds(self):
        for arguments in (
            ("--head", "HEAD"),
            ("--json",),
            ("--dry-run", "--all"),
            ("--dry-run", "--no-build"),
        ):
            result = self.fixture.run("test", *arguments)
            self.assertNotEqual(0, result.returncode)
            self.assertIn("error:", result.stderr)
            self.assertEqual("", self.fixture.command_log())
        result = self.fixture.run("test", "--dry-run", PACKAGE_STATUS="3")
        self.assertNotEqual(0, result.returncode)
        self.assertIn("./test --everything", result.stderr)
        self.assertNotIn("xcodebuild", self.fixture.command_log())

    def test_git_failure_is_not_an_empty_selection(self):
        (self.fixture.bin / "git").unlink()
        self.fixture._write_executable(self.fixture.bin / "git", "#!/bin/sh\nexit 2\n")
        self.assertEqual("full", self.preview()["mode"])


if __name__ == "__main__":
    unittest.main()
