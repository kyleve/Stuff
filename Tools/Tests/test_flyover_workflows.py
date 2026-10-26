from pathlib import Path
import unittest

from Tools.repository import repository_root


class FlyoverWorkflowTests(unittest.TestCase):
    def test_daily_controller_and_shared_pages_are_wired(self):
        root = repository_root(__file__)
        daily = (root / '.github/workflows/flyover-daily.yml').read_text()
        self.assertIn("cron: '23 9 * * *'", daily)
        self.assertIn("github.ref == 'refs/heads/main'", daily)
        self.assertIn('persist-credentials: false', daily)
        self.assertIn('Tools.flyover_distribution', daily)
        self.assertNotIn('deploy-pages', daily)
        pages = (root / '.github/workflows/installer-pages.yml').read_text()
        self.assertLess(pages.index('Tools.flyover_pages'), pages.index('actions/upload-pages-artifact'))

    def test_unsigned_worker_is_main_only_and_serial(self):
        text = (repository_root(__file__) / '.circleci/config.yml').read_text()
        job = text.split('  export-flyover:', 1)[1].split('  archive-app:', 1)[0]
        self.assertIn('Tools.flyover_ci', job)
        self.assertNotIn('context:', job)
        self.assertNotIn('parallelism:', job)
        workflow = text.split('  "Flyover Export":', 1)[1].split('  "iOS CI":', 1)[0]
        self.assertIn('pipeline.config.ref == "refs/heads/main"', workflow)
        self.assertIn('pipeline.event.name == "api"', workflow)
