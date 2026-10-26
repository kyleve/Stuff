import unittest

from Tools.circleci_pipeline import CircleCI
from Fixtures.circleci_distribution_fixtures import PROJECT, PIPELINE, CircleCIServer, ARTIFACT_URL


class CircleCIPipelineTests(unittest.TestCase):
    def test_selection_is_configured_by_consumer(self):
        server = CircleCIServer()
        server.workflows[0]['name'] = 'Flyover Export'
        server.jobs[0]['name'] = 'Export Flyover'
        server.artifacts[0]['path'] = 'flyover/atlases.zip'
        client = CircleCI(PROJECT, 'token', server, workflow='Flyover Export',
                         job='Export Flyover', artifact='flyover/atlases.zip')
        self.assertEqual(client.artifact(PIPELINE), ARTIFACT_URL)
