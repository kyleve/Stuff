import io
import unittest
from unittest.mock import Mock
from urllib.error import HTTPError

from Tools.circleci_pipeline import CircleCI, wait_for_archive
from Fixtures.circleci_distribution_fixtures import (
    PROJECT,
    PIPELINE,
    CircleCIServer,
    ARTIFACT_URL,
    setup_workflow,
    WORKFLOW,
)


class CircleCIPipelineTests(unittest.TestCase):
    def test_setup_failure_stops_polling_before_publication_workflow_exists(self):
        for status in ("failed", "canceled", "error", "unauthorized", "not_run"):
            for workflow in ("Installer Archive", "Flyover Export"):
                with self.subTest(status=status, workflow=workflow):
                    server = CircleCIServer()
                    server.pipeline["state"] = "setup"
                    server.workflows = [setup_workflow(status)]
                    client = CircleCI(
                        PROJECT,
                        "token",
                        server,
                        workflow=workflow,
                        job="unused",
                        artifact="unused",
                    )
                    sleep = Mock()
                    with self.assertRaisesRegex(
                        ValueError, f"setup workflow ended with status {status}"
                    ):
                        wait_for_archive(
                            client,
                            PIPELINE,
                            clock=Mock(side_effect=[0, 0, 3601]),
                            sleep=sleep,
                        )
                    sleep.assert_not_called()
                    self.assertEqual(len(server.requests), 2)

    def test_setup_and_continuation_can_finish_between_polls(self):
        for status in ("running", "on_hold", "failing", "success"):
            with self.subTest(status=status):
                server = CircleCIServer()
                publication = server.workflows.pop()
                server.pipeline["state"] = "setup"
                setup = setup_workflow(status)
                server.workflows = [setup]
                client = CircleCI(
                    PROJECT,
                    "token",
                    server,
                    workflow="Installer Archive",
                    job="Archive App",
                    artifact="installer/app.ipa",
                )

                def continue_pipeline(_):
                    server.pipeline["state"] = "created"
                    setup["status"] = "success"
                    server.workflows.append(publication)

                sleep = Mock(side_effect=continue_pipeline)
                self.assertEqual(
                    wait_for_archive(
                        client,
                        PIPELINE,
                        clock=Mock(side_effect=[0, 0, 15]),
                        sleep=sleep,
                    ),
                    ARTIFACT_URL,
                )
                sleep.assert_called_once_with(15)

    def test_only_setup_tagged_failures_block_a_missing_publication(self):
        server = CircleCIServer()
        client = CircleCI(
            PROJECT,
            "token",
            server,
            workflow="Installer Archive",
            job="Archive App",
            artifact="installer/app.ipa",
        )
        server.workflows = []
        self.assertIsNone(client.artifact(PIPELINE))
        setup = setup_workflow("failed")
        del setup["tag"]
        server.workflows = [setup]
        self.assertIsNone(client.artifact(PIPELINE))
        setup.update(tag="setup", name="Renamed setup workflow")
        with self.assertRaisesRegex(
            ValueError, "setup workflow ended with status failed"
        ):
            client.artifact(PIPELINE)

    def test_existing_publication_takes_precedence_over_setup_failure(self):
        server = CircleCIServer()
        server.workflows.append(setup_workflow("failed"))
        client = CircleCI(
            PROJECT,
            "token",
            server,
            workflow="Installer Archive",
            job="Archive App",
            artifact="installer/app.ipa",
        )
        server.workflows[0]["status"] = "running"
        self.assertIsNone(client.artifact(PIPELINE))
        server.workflows[0]["status"] = "success"
        self.assertEqual(client.artifact(PIPELINE), ARTIFACT_URL)

    def test_selection_is_configured_by_consumer(self):
        server = CircleCIServer()
        server.workflows[0]["name"] = "Flyover Export"
        server.jobs[0]["name"] = "Export Flyover"
        server.artifacts[0]["path"] = "flyover/atlases.zip"
        client = CircleCI(
            PROJECT,
            "token",
            server,
            workflow="Flyover Export",
            job="Export Flyover",
            artifact="flyover/atlases.zip",
        )
        self.assertEqual(client.artifact(PIPELINE), ARTIFACT_URL)

    def client(self, transport):
        return CircleCI(
            PROJECT,
            "token",
            transport,
            workflow="Installer Archive",
            job="Archive App",
            artifact="installer/app.ipa",
        )

    def test_discovery_404_retries_the_same_pipeline_without_retriggering(self):
        for path in (f"pipeline/{PIPELINE}", f"pipeline/{PIPELINE}/workflow"):
            with self.subTest(path=path):
                server = CircleCIServer()
                missing = True
                error = HTTPError(
                    "https://circleci.com/discovery", 404, "not ready", {}, io.BytesIO()
                )
                self.addCleanup(error.close)

                def transport(request):
                    nonlocal missing
                    if missing and request.full_url.endswith(path):
                        missing = False
                        raise error
                    return server(request)

                sleep = Mock()
                self.assertEqual(
                    wait_for_archive(
                        self.client(transport), PIPELINE, clock=lambda: 0, sleep=sleep
                    ),
                    ARTIFACT_URL,
                )
                sleep.assert_called_once_with(15)
                self.assertTrue(error.closed)
                self.assertTrue(all(call.method == "GET" for call in server.requests))

    def test_persistent_discovery_404_reaches_the_polling_deadline(self):
        for path in (f"pipeline/{PIPELINE}", f"pipeline/{PIPELINE}/workflow"):
            with self.subTest(path=path):
                server = CircleCIServer()

                def transport(request):
                    if request.full_url.endswith(path):
                        raise HTTPError(
                            request.full_url, 404, "not ready", {}, io.BytesIO()
                        )
                    return server(request)

                ticks = iter([0, 0, 15, 30])
                sleep = Mock()
                with self.assertRaisesRegex(ValueError, "timed out"):
                    wait_for_archive(
                        self.client(transport),
                        PIPELINE,
                        timeout=30,
                        clock=lambda: next(ticks),
                        sleep=sleep,
                    )
                self.assertEqual(sleep.call_count, 2)

    def test_other_http_failures_propagate_without_retry(self):
        cases = [
            (path, code)
            for path in (f"pipeline/{PIPELINE}", f"pipeline/{PIPELINE}/workflow")
            for code in (401, 403, 429, 500)
        ] + [
            (f"workflow/{WORKFLOW}/job", 404),
            (f"project/{PROJECT}/7/artifacts", 404),
        ]
        for path, code in cases:
            with self.subTest(path=path, code=code):
                server = CircleCIServer()
                error = HTTPError(
                    "https://circleci.com/secret", code, "secret", {}, None
                )

                def transport(request):
                    if request.full_url.endswith(path):
                        raise error
                    return server(request)

                sleep = Mock()
                with self.assertRaises(HTTPError) as raised:
                    wait_for_archive(
                        self.client(transport), PIPELINE, clock=lambda: 0, sleep=sleep
                    )
                self.assertIs(raised.exception, error)
                sleep.assert_not_called()
