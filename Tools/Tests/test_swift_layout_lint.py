"""Regression coverage for the two layouts SwiftFormat leaves in place."""

from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(shutil.which("xcrun"), "requires Xcode's SwiftSyntax")
class SwiftLayoutLintTests(unittest.TestCase):
    def test_tracked_swift_files_follow_repository_layout(self):
        subprocess.run(
            [sys.executable, "-m", "Tools.swift_layout_lint"],
            cwd=Path(__file__).resolve().parents[2],
            check=True,
        )

    def test_flags_inline_enum_and_mixed_host_call_only(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Layout.swift"
            source.write_text(
                """enum Mode { case detail }
ObservableHostingView({ makeModel() }) { model in show(model) }
enum Mode {
    case detail
}
enum Namespace {}
ObservableHostingView { makeModel() } content: { model in show(model) }
ObservableHostingView(makeModel) { model in show(model) }
OtherHost({ makeModel() }) { model in show(model) }
// enum Comment { case detail }
let example = "ObservableHostingView({ model }) { content }"
enum Partial { case detail
}
Module.ObservableHostingView<Model, Content>.init({ makeModel() }) { show($0) }
enum Node {
    indirect case link(Node), branch(Node)
    @available(*, deprecated) case first, second
}
"""
            )
            result = subprocess.run(
                [sys.executable, "-m", "Tools.swift_layout_lint", str(source)],
                cwd=Path(__file__).resolve().parents[2],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertEqual(
                result.stdout.splitlines(),
                [
                    f"{source}:1:13: error: Place enum cases on separate lines inside the braces.",
                    f"{source}:2:1: error: Use a trailing factory closure followed by content: {{ … }}.",
                    f"{source}:12:16: error: Place enum cases on separate lines inside the braces.",
                    f"{source}:14:1: error: Use a trailing factory closure followed by content: {{ … }}.",
                    f"{source}:16:31: error: Split grouped enum cases and repeat any shared modifiers or attributes.",
                    f"{source}:17:43: error: Split grouped enum cases and repeat any shared modifiers or attributes.",
                ],
            )
