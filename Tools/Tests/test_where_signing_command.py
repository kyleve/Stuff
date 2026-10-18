"""The CI lifecycle wrapper needs only the system Ruby, including during cleanup."""
from pathlib import Path
import subprocess
import unittest
from Tools.repository import repository_root


class WhereSigningCommandTests(unittest.TestCase):
    def test_invalid_command_and_local_use_do_not_access_credentials(self):
        command = repository_root(Path(__file__)) / '.github/where-signing.sh'
        for arguments, message in (([], 'Usage:'), (['prepare'], 'CircleCI')):
            result = subprocess.run(['/bin/bash', str(command), *arguments], cwd='/tmp',
                                    env={'PATH': '/usr/bin:/bin'}, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(message, result.stderr)
