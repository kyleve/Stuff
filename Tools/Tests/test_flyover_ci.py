from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from Tools.flyover_apps import FlyoverApp
from Tools.flyover_ci import build
from Tools.Tests.flyover_bundle_support import SHA


class FlyoverCITests(unittest.TestCase):
    def test_checkout_mismatch_stops_before_capture(self):
        with patch('Tools.flyover_ci.subprocess.check_output', return_value='wrong'), \
             patch('Tools.flyover_ci.subprocess.run') as run:
            with self.assertRaisesRegex(ValueError, 'checkout differs'):
                build(Path('/unused/atlases.zip'), SHA)
            run.assert_not_called()

    def test_all_registered_apps_capture_serially_before_packaging(self):
        apps = (FlyoverApp('one', 'One', 'One/Export/capture()'), FlyoverApp('two', 'Two', 'Two/Export/capture()'))
        events = []
        with tempfile.TemporaryDirectory() as temporary, \
             patch('Tools.flyover_ci.subprocess.check_output', return_value=SHA), \
             patch('Tools.flyover_ci.load_apps', return_value=apps), \
             patch('Tools.flyover_ci.subprocess.run', side_effect=lambda argv, **kwargs: events.append(argv[3])), \
             patch('Tools.flyover_ci.pack_bundle', side_effect=lambda *args: events.append('pack')):
            build(Path(temporary) / 'atlases.zip', SHA)
        self.assertEqual(events, ['one', 'two', 'pack'])
