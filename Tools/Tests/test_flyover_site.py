"""Production Astro builds and the public preview boundary, without simulator captures."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
import signal
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from Tools import flyover_site
from Tools.flyover_manifest import validate_artifact
from Tools.Tests.flyover_test_support import create_flyover_artifact


class FlyoverSiteTests(unittest.TestCase):
    def test_interrupt_stops_child_restores_handlers_and_removes_workspace(self):
        for number in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=number), tempfile.TemporaryDirectory() as temporary:
                atlas = create_flyover_artifact(Path(temporary))
                workspaces = []
                handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}

                class Child:
                    pid = 123456
                    stopped = False

                    def poll(self):
                        return 0 if self.stopped else None

                    def wait(self, timeout=None):
                        if timeout is None and not self.stopped:
                            signal.getsignal(number)(number, None)
                        self.stopped = True
                        return 0

                def launch(*args, **kwargs):
                    workspaces.append(Path(kwargs['env']['FLYOVER_SITE_CACHE']).parent)
                    self.assertTrue(kwargs['start_new_session'])
                    return Child()

                with patch('Tools.flyover_site.subprocess.Popen', side_effect=launch), \
                        patch('Tools.flyover_site.os.killpg') as stop, redirect_stdout(io.StringIO()):
                    self.assertEqual(flyover_site.main(['preview', str(atlas)]), 128 + number)
                stop.assert_called_once_with(123456, signal.SIGTERM)
                self.assertTrue(all(not path.exists() for path in workspaces))
                self.assertEqual({sig: signal.getsignal(sig) for sig in handlers}, handlers)

    def test_real_build_uses_relative_bundled_assets_and_json_only(self):
        with tempfile.TemporaryDirectory(prefix="flyover build ü ") as temporary:
            output = Path(temporary)
            flyover_site.build_shell(output)
            html = (output / "index.html").read_text()
            assets = json.loads((output / "web-assets.json").read_text())
            self.assertIn('type="module"', html)
            self.assertNotIn('src="/', html)
            self.assertNotIn('href="/', html)
            self.assertNotIn('https://', html)
            self.assertNotIn('manifest.js', html)
            self.assertTrue(any(path.endswith('.css') for path in assets))
            self.assertTrue(any(path.endswith('.js') for path in assets))
            for relative in assets:
                self.assertTrue((output / relative).is_file())
                self.assertIn('./' + relative, html)
            script = '\n'.join((output / path).read_text() for path in assets if path.endswith('.js'))
            self.assertIn('manifest.json', script)
            self.assertNotIn('FLYOVER_MANIFEST', script)

    def test_failed_build_does_not_copy_partial_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            with patch('Tools.flyover_site.subprocess.run', return_value=subprocess.CompletedProcess([], 17, 'partial', 'failed')):
                with self.assertRaisesRegex(ValueError, 'Astro build failed.*17'):
                    flyover_site.build_shell(output)
            self.assertEqual(list(output.iterdir()), [])

    def test_private_copy_excludes_unlisted_files_and_survives_source_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            source.mkdir()
            create_flyover_artifact(source)
            (source / 'secret.txt').write_text('SECRET')
            artifact = validate_artifact(source)
            output = root / 'copy'
            flyover_site.copy_artifact(artifact, output, captures_only=False)
            self.assertEqual({str(path.relative_to(output)) for path in output.rglob('*') if path.is_file()}, set(artifact.allowed_paths))
            (source / 'manifest.json').write_text('SECRET')
            self.assertNotIn('SECRET', (output / 'manifest.json').read_text())
            dev = root / 'dev'
            # The original validated file set is restored before a second copy.
            (source / 'manifest.json').write_bytes((output / 'manifest.json').read_bytes())
            flyover_site.copy_artifact(artifact, dev, captures_only=True)
            self.assertFalse((dev / 'index.html').exists())
            self.assertTrue((dev / 'manifest.json').exists())

    def test_public_preview_uses_isolated_roots_and_propagates_status(self):
        for mode, lan in [('preview', False), ('dev', True)]:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix='flyover preview ü ') as temporary:
                root = Path(temporary)
                atlas = root / 'atlas'
                atlas.mkdir()
                create_flyover_artifact(atlas)
                fake = root / 'mise data/bin/mise'
                fake.parent.mkdir(parents=True)
                fake.write_text(f'#!{sys.executable}\n' + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
workspace = Path(args[args.index('--root') + 1])
output = Path(args[args.index('--outDir') + 1])
public = Path(os.environ['FLYOVER_SITE_PUBLIC'])
Path(os.environ['FLYOVER_TEST_LOG']).write_text(json.dumps({
    'arguments': args, 'workspace': str(workspace),
    'preview': (output / 'manifest.json').is_file(),
    'dev': (public / 'manifest.json').is_file(),
    'telemetry': os.environ['ASTRO_TELEMETRY_DISABLED'],
}))
sys.exit(17)
''')
                fake.chmod(0o755)
                log = root / 'arguments.json'
                command = [str(flyover_site.ROOT / 'flyover'), mode, '--output', str(atlas), '--port', '4444']
                if lan:
                    command.append('--lan')
                result = subprocess.run(command, cwd=root, capture_output=True, text=True,
                                        env={**os.environ, 'PATH': '/usr/bin:/bin', 'MISE_DATA_DIR': str(fake.parent.parent),
                                             'FLYOVER_TEST_LOG': str(log)})
                self.assertEqual(result.returncode, 17, result.stderr)
                value = json.loads(log.read_text())
                self.assertIn('0.0.0.0' if lan else '127.0.0.1', value['arguments'])
                self.assertTrue(value[mode])
                self.assertEqual(value['telemetry'], '1')
                self.assertFalse(Path(value['workspace']).exists())

    def test_invalid_input_does_not_start_astro(self):
        with patch('Tools.flyover_site.subprocess.Popen') as launch, redirect_stderr(io.StringIO()):
            self.assertEqual(flyover_site.main(['preview', '/nonexistent-flyover-atlas']), 1)
        launch.assert_not_called()

    def test_concurrent_shell_builds_have_independent_workspaces(self):
        from concurrent.futures import ThreadPoolExecutor
        with tempfile.TemporaryDirectory() as temporary:
            outputs = [Path(temporary) / name for name in ('first', 'second')]
            for output in outputs:
                output.mkdir()
            with ThreadPoolExecutor(max_workers=2) as executor:
                list(executor.map(flyover_site.build_shell, outputs))
            self.assertEqual((outputs[0] / 'index.html').read_bytes(), (outputs[1] / 'index.html').read_bytes())
            self.assertEqual((outputs[0] / 'web-assets.json').read_bytes(), (outputs[1] / 'web-assets.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
