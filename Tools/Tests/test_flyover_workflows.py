from pathlib import Path
import json
import subprocess
import unittest

from Tools.repository import repository_root


class FlyoverWorkflowTests(unittest.TestCase):
    def test_credential_diagnostic_does_not_read_header_values(self):
        text = (repository_root(__file__) / '.circleci/config.yml').read_text()
        diagnostic = text.split('  validate_build_environment:', 1)[1].split('  validate_simulator_environment:', 1)[0]
        self.assertIn("git config --local --name-only --get-regexp 'credential|extraheader'", diagnostic)
        self.assertNotIn('sed -E', diagnostic)

    def test_publication_jobs_never_restore_or_save_shared_caches(self):
        path = repository_root(__file__) / '.circleci/config.yml'
        config = json.loads(subprocess.check_output(
            ['ruby', '-ryaml', '-rjson', '-e', 'puts JSON.generate(YAML.load_file(ARGV.fetch(0)))', str(path)], text=True))

        def cache_steps(steps, parameters):
            found = []
            for step in steps:
                if not isinstance(step, dict):
                    continue
                for name, value in step.items():
                    if name in ('restore_cache', 'save_cache'):
                        found.append(name)
                    elif name == 'when':
                        parameter = value['condition'].removeprefix('<< parameters.').removesuffix(' >>')
                        if parameters[parameter]:
                            found.extend(cache_steps(value['steps'], parameters))
                    elif name in config['commands']:
                        command = config['commands'][name]
                        arguments = {key: item.get('default') for key, item in command.get('parameters', {}).items()}
                        arguments.update(value or {})
                        found.extend(cache_steps(command['steps'], arguments))
            return found

        for job in ('export-flyover', 'archive-app'):
            self.assertEqual(cache_steps(config['jobs'][job]['steps'], {}), [], job)
        # Ordinary CI still gets all three restore/save pairs.
        self.assertEqual(cache_steps(config['commands']['prepare_builder']['steps'],
                                    {'use_caches': True, 'require_simulator': True}).count('restore_cache'), 3)
        self.assertEqual(cache_steps(config['commands']['prepare_builder']['steps'],
                                    {'use_caches': True, 'require_simulator': True}).count('save_cache'), 3)

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
