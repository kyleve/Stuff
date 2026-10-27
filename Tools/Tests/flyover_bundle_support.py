import json

from Tools.Tests.flyover_test_support import create_flyover_artifact


SHA = "a" * 40


def create_bundle(root, app_ids=("where", "second")):
    root.mkdir()
    for app_id in app_ids:
        atlas = create_flyover_artifact(root / app_id)
        manifest = json.loads((atlas / "manifest.json").read_text())
        manifest["application"]["id"] = app_id
        manifest["build"]["commit"] = SHA
        (atlas / "manifest.json").write_text(json.dumps(manifest))
    (root / "publication.json").write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "commit": SHA,
                "apps": [{"id": app_id, "title": app_id} for app_id in app_ids],
            }
        )
    )
    return root
