from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from test_impact_graph import affected, catalog, target_graph
from Fixtures.test_impact_fixtures import metadata


class ImpactGraphTests(unittest.TestCase):
    def test_reads_pinned_export_and_rejects_unknown_nodes(self):
        text = 'digraph {\n "Stuff:Tests" -> { "Stuff:UI" }\n}'
        self.assertEqual(target_graph(text, {"Tests", "UI"}), {"Tests": ["UI"], "UI": []})
        with self.assertRaises(ValueError):
            target_graph(text, {"Tests"})
        with self.assertRaises(ValueError):
            target_graph("digraph {}", {"Tests"})

    def test_unrecognized_file_and_ci_change_never_select_nothing(self):
        graph = metadata()["catalog"]
        for path in ["Tools/InstallerKit/site.css", ".circleci/config.yml", "random.swift"]:
            self.assertEqual(affected([graph], [path])[0], set(graph["bundles"]))

    def test_resources_and_generator_inputs_are_explicit(self):
        root = Path("/checkout")
        targets = {"ToolsSnapshotTests": {"product": "unit_tests", "deploymentTargets": {"iOS": "27"},
                                          "sources": [{"path": "/checkout/Tools/SnapshotTests/SiteTests.swift"}],
                                          "dependencies": [{"package": {"product": "UI"}}]}}
        package = {"targets": [{"name": "UI", "path": "UI/Sources", "type": "regular", "dependencies": []}]}
        graph = catalog(root, {"projects": ["/checkout", {"targets": targets}]}, package,
                        ' "Stuff:ToolsSnapshotTests" -> { "Stuff:UI" }',
                        ["UI/Sources/Resources/strings.json", "Tools/SnapshotTests/SiteTests.swift", "Tools/InstallerKit/site.css"])
        inputs = graph["bundles"]["ToolsSnapshotTests"]["inputs"]
        self.assertIn("Tools/InstallerKit/site.css", inputs)
        self.assertIn("UI/Sources/Resources/strings.json", inputs)
        with self.assertRaises(ValueError):
            catalog(root, {"projects": ["/checkout", {"targets": targets}]}, package,
                    ' "Stuff:ToolsSnapshotTests" -> { }', [])
