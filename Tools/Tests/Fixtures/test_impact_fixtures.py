"""Small graph with two snapshots in one production target and an unrelated bundle."""


def metadata(revision="head"):
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from test_impact_graph import digest

    sources = ["UI/Card.swift", "UI/Other.swift", "UI/Helper.swift", "UI/CardTests.swift", "UI/OtherTests.swift"]
    suites = {"UISnapshotTests/CardTests": "UI/CardTests.swift", "UISnapshotTests/OtherTests": "UI/OtherTests.swift"}
    bundles = {
        "UISnapshotTests": {"inputs": sources + ["UI/Resources/copy.json"], "sources": sources, "platform": "iOS"},
        "UITests": {"inputs": sources[:3], "sources": sources[:3], "platform": "iOS"},
        "LedgerTests": {"inputs": ["Ledger/Value.swift"], "sources": ["Ledger/Value.swift"], "platform": "macOS"},
    }
    edges = {"UI/Card.swift": ["UI/Helper.swift"], "UI/Other.swift": [], "UI/Helper.swift": [],
             "UI/CardTests.swift": ["UI/Card.swift"], "UI/OtherTests.swift": ["UI/Other.swift"]}
    return {"version": 1, "revision": revision, "indexRevision": revision, "dirty": False, "environment": {"xcode": "pinned"},
            "seconds": 1, "blobs": {},
            "catalog": {"bundles": bundles, "suites": suites, "graph": {},
                        "inventory": digest({"bundles": bundles, "suites": suites})},
            "index": [{"path": path, "indexed": True, "definitions": ["symbol:" + path], "dependencies": edges[path],
                       "syntax": {"captures": ["Card"] if path.endswith("Tests.swift") else [], "risks": [], "declarations": [], "shape": []}}
                      for path in sources]}
