import json
import subprocess
import unittest

from Tools.repository import repository_root


class FlyoverWorkflowTests(unittest.TestCase):
    def test_credential_diagnostic_does_not_read_header_values(self):
        text = (repository_root(__file__) / ".circleci/jobs.yml").read_text()
        diagnostic = text.split("  validate_build_environment:", 1)[1].split(
            "  validate_simulator_environment:", 1
        )[0]
        self.assertIn(
            "git config --local --name-only --get-regexp 'credential|extraheader'",
            diagnostic,
        )
        self.assertNotIn("sed -E", diagnostic)

    def test_publication_jobs_never_restore_or_save_shared_caches(self):
        path = repository_root(__file__) / ".circleci/jobs.yml"
        config = json.loads(
            subprocess.check_output(
                [
                    "ruby",
                    "-ryaml",
                    "-rjson",
                    "-e",
                    "puts JSON.generate(YAML.load_file(ARGV.fetch(0)))",
                    str(path),
                ],
                text=True,
            )
        )

        def cache_steps(steps, parameters):
            found = []
            for step in steps:
                if not isinstance(step, dict):
                    continue
                for name, value in step.items():
                    if name in ("restore_cache", "save_cache"):
                        found.append(name)
                    elif name == "when":
                        parameter = (
                            value["condition"]
                            .removeprefix("<< parameters.")
                            .removesuffix(" >>")
                        )
                        if parameters[parameter]:
                            found.extend(cache_steps(value["steps"], parameters))
                    elif name in config["commands"]:
                        command = config["commands"][name]
                        arguments = {
                            key: item.get("default")
                            for key, item in command.get("parameters", {}).items()
                        }
                        arguments.update(value or {})
                        found.extend(cache_steps(command["steps"], arguments))
            return found

        for job in ("export-flyover", "archive-app"):
            self.assertEqual(cache_steps(config["jobs"][job]["steps"], {}), [], job)
        # Ordinary CI still gets all three restore/save pairs.
        self.assertEqual(
            cache_steps(
                config["commands"]["prepare_builder"]["steps"],
                {"use_caches": True, "require_simulator": True},
            ).count("restore_cache"),
            3,
        )
        self.assertEqual(
            cache_steps(
                config["commands"]["prepare_builder"]["steps"],
                {"use_caches": True, "require_simulator": True},
            ).count("save_cache"),
            3,
        )

    def test_unsigned_worker_is_serial_and_has_no_credentials(self):
        text = (repository_root(__file__) / ".circleci/jobs.yml").read_text()
        job = text.split("  export-flyover:", 1)[1].split("  archive-app:", 1)[0]
        self.assertIn("Tools.flyover_ci", job)
        self.assertNotIn("context:", job)
        self.assertNotIn("parallelism:", job)
        self.assertIn("persist_to_workspace", job)
