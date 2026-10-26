import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

from Tools.flyover_distribution import CaptureRequest, download, main, publish
from Tools.Tests.flyover_bundle_support import SHA


class FlyoverDistributionTests(unittest.TestCase):
    def test_controller_errors_do_not_log_signed_urls(self):
        environment = {key: 'test' for key in ('CIRCLECI_PROJECT', 'CIRCLECI_PIPELINE',
                       'GITHUB_REPOSITORY', 'GITHUB_RUN_ID', 'GITHUB_RUN_ATTEMPT')}
        with patch.dict('os.environ', environment), patch('sys.stderr', new_callable=io.StringIO) as output, \
             patch('Tools.flyover_distribution.publish', side_effect=HTTPError('https://host/secret', 403, 'secret', {}, None)):
            self.assertEqual(main(['--sha', SHA]), 1)
        self.assertIn('HTTP 403', output.getvalue())
        self.assertNotIn('secret', output.getvalue())

    def test_failed_upload_never_publishes_or_dispatches(self):
        import subprocess
        with patch.dict('os.environ', {'CIRCLECI_TOKEN': 'token'}), \
             patch('Tools.flyover_distribution.CircleCI'), \
             patch('Tools.flyover_distribution.wait_for_archive', return_value='url'), \
             patch('Tools.flyover_distribution.download'), \
             patch('Tools.flyover_distribution.unpack_bundle'), \
             patch('Tools.flyover_distribution.subprocess.run', side_effect=subprocess.CalledProcessError(1, 'gh')) as run:
            with self.assertRaises(subprocess.CalledProcessError):
                publish('project', 'definition', 'owner/repo', SHA, '10', '1')
            self.assertEqual(run.call_count, 1)

    def test_request_only_enables_unsigned_flyover_workflow(self):
        self.assertEqual(CaptureRequest(SHA).parameters, {'flyover_export': 'true', 'flyover_sha': SHA})
        with self.assertRaises(ValueError):
            CaptureRequest('main')

    def test_release_is_published_only_after_validation_and_upload(self):
        events = []
        client = Mock(token='token')
        with patch.dict('os.environ', {'CIRCLECI_TOKEN': 'token'}), \
             patch('Tools.flyover_distribution.CircleCI', return_value=client), \
             patch('Tools.flyover_distribution.wait_for_archive', return_value='url'), \
             patch('Tools.flyover_distribution.download', side_effect=lambda *args: events.append('download')), \
             patch('Tools.flyover_distribution.unpack_bundle', side_effect=lambda *args: events.append('validate')), \
             patch('Tools.flyover_distribution.subprocess.run', side_effect=lambda argv, **kwargs: events.append(argv)):
            publish('project', 'definition', 'owner/repo', SHA, '10', '2')
        self.assertEqual(events[:2], ['download', 'validate'])
        self.assertIn('--draft', events[2])
        self.assertEqual(events[3][-1], '--draft=false')
        self.assertEqual(events[4][1:4], ['workflow', 'run', 'installer-pages.yml'])

    def test_failed_capture_validation_never_creates_a_release(self):
        with patch.dict('os.environ', {'CIRCLECI_TOKEN': 'token'}), \
             patch('Tools.flyover_distribution.CircleCI'), \
             patch('Tools.flyover_distribution.wait_for_archive', return_value='url'), \
             patch('Tools.flyover_distribution.download'), \
             patch('Tools.flyover_distribution.unpack_bundle', side_effect=ValueError('invalid')), \
             patch('Tools.flyover_distribution.subprocess.run') as run:
            with self.assertRaises(ValueError):
                publish('project', 'definition', 'owner/repo', SHA, '10', '1')
            run.assert_not_called()

    def test_download_is_bounded_and_does_not_redirect_credentials(self):
        with tempfile.TemporaryDirectory() as temporary, \
             patch('Tools.flyover_distribution.build_opener') as opener, \
             patch('Tools.flyover_distribution.MAX_BYTES', 2):
            opener.return_value.open.return_value = io.BytesIO(b'123')
            with self.assertRaisesRegex(ValueError, 'size budget'):
                download('https://output.circle-artifacts.com/atlas', Path(temporary) / 'atlas.zip', 'token')
            request = opener.return_value.open.call_args.args[0]
            self.assertEqual(request.headers, {})
            self.assertEqual(request.get_header('Circle-token'), 'token')
