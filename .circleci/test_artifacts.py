#!/usr/bin/env python3
"""Create and validate the portable iOS test-build manifest."""

import argparse
import json
import pathlib
import platform
import subprocess
import sys


FORMAT_VERSION = 2


def command_output(*command):
    return subprocess.run(command, capture_output=True, check=True, text=True).stdout.strip()


def environment_metadata():
    xcode_lines = command_output("xcodebuild", "-version").splitlines()
    build_line = next(line for line in xcode_lines if line.startswith("Build version "))
    return {
        "checkout": str(pathlib.Path.cwd().resolve()),
        "commit": command_output("git", "rev-parse", "HEAD"),
        "xcodeBuild": build_line.removeprefix("Build version "),
        "sdkBuild": command_output(
            "xcrun", "--sdk", "iphonesimulator", "--show-sdk-build-version"
        ),
        "architecture": platform.machine(),
        "configuration": "Debug",
    }


def create_manifest(root, schemes, metadata=None):
    root = root.resolve()
    products_root = root / "DerivedData" / "Build" / "Products"
    built_products = products_root / "Debug-iphonesimulator"
    if not built_products.is_dir():
        raise ValueError(f"test products do not exist: {built_products}")

    resolved_schemes = {}
    for scheme in schemes:
        candidates = sorted(products_root.glob(f"{scheme}_*.xctestrun"))
        if len(candidates) != 1:
            raise ValueError(
                f"expected one .xctestrun for {scheme}, found {len(candidates)} "
                f"in {products_root}"
            )
        resolved_schemes[scheme] = str(candidates[0].relative_to(root))

    manifest = {
        "formatVersion": FORMAT_VERSION,
        "artifactRoot": str(root),
        "productsRoot": str(products_root.relative_to(root)),
        "builtProducts": str(built_products.relative_to(root)),
        "schemes": resolved_schemes,
        **(metadata or environment_metadata()),
    }
    manifest_path = root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


def load_and_validate(root, metadata=None):
    root = root.resolve()
    manifest_path = root / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text())
    except FileNotFoundError as error:
        raise ValueError(f"test artifact manifest does not exist: {manifest_path}") from error
    except json.JSONDecodeError as error:
        raise ValueError(f"test artifact manifest is not valid JSON: {error}") from error

    if manifest.get("formatVersion") != FORMAT_VERSION:
        raise ValueError(
            f"unsupported test artifact formatVersion {manifest.get('formatVersion')}; "
            f"expected {FORMAT_VERSION}"
        )
    if manifest.get("artifactRoot") != str(root):
        raise ValueError(
            f"test artifacts were built at {manifest.get('artifactRoot')}; attached at {root}"
        )

    products_root_value = manifest.get("productsRoot")
    built_products_value = manifest.get("builtProducts")
    schemes = manifest.get("schemes")
    if not isinstance(products_root_value, str) or not products_root_value:
        raise ValueError("test artifact manifest has no products root")
    if not isinstance(built_products_value, str) or not built_products_value:
        raise ValueError("test artifact manifest has no built-products path")
    if not isinstance(schemes, dict) or not schemes:
        raise ValueError("test artifact manifest has no scheme mapping")

    expected = metadata or environment_metadata()
    for key, value in expected.items():
        if manifest.get(key) != value:
            raise ValueError(
                f"test artifact {key} is {manifest.get(key)!r}; current value is {value!r}"
            )

    products_root = (root / products_root_value).resolve()
    built_products = (root / built_products_value).resolve()
    for name, path in (("products root", products_root), ("built products", built_products)):
        if not path.is_relative_to(root):
            raise ValueError(f"test {name} path leaves the artifact root: {path}")
        if not path.is_dir():
            raise ValueError(f"test {name} do not exist: {path}")
    for scheme, relative_path in schemes.items():
        if not isinstance(scheme, str) or not isinstance(relative_path, str):
            raise ValueError("test artifact scheme mapping must contain string paths")
        path = (root / relative_path).resolve()
        if not path.is_relative_to(root):
            raise ValueError(f"test run path leaves the artifact root: {path}")
        if not path.is_file():
            raise ValueError(f"test run file for {scheme} does not exist: {path}")
    return manifest


def resolved_path(root, scheme, field, metadata=None):
    root = root.resolve()
    manifest = load_and_validate(root, metadata)
    if scheme not in manifest["schemes"]:
        raise ValueError(f"test artifact manifest has no scheme named {scheme}")
    if field == "products":
        return root / manifest["builtProducts"]
    return root / manifest["schemes"][scheme]


def suite_identifiers(document):
    suites = set()

    def walk(node, bundle=None, suite=None):
        if isinstance(node, list):
            for child in node:
                walk(child, bundle, suite)
            return
        if not isinstance(node, dict):
            return

        identifier = str(node.get("identifier", ""))
        name = str(node.get("name", ""))
        candidate = identifier or name
        kind = node.get("kind")
        if kind == "target":
            bundle = name
            suite = None
        elif kind == "class" and bundle:
            suite = name
        elif kind == "test" and bundle and suite:
            suites.add(f"{bundle}/{suite}")
        elif candidate.endswith(".xctest"):
            bundle = candidate.removesuffix(".xctest")
            suite = None
        elif bundle and node.get("children") and candidate not in {"All tests", bundle}:
            suite = candidate.split("/")[-1]
        elif bundle and suite and not node.get("children"):
            suites.add(f"{bundle}/{suite}")

        if "children" in node:
            for child in node.get("children", []):
                walk(child, bundle, suite)
        else:
            for value in node.values():
                if isinstance(value, (dict, list)):
                    walk(value, bundle, suite)

    walk(document)
    return sorted(suites)


def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    create = subparsers.add_parser("create")
    create.add_argument("--root", type=pathlib.Path, required=True)
    create.add_argument("--scheme", action="append", required=True)

    resolve = subparsers.add_parser("resolve")
    resolve.add_argument("--root", type=pathlib.Path, required=True)
    resolve.add_argument("--scheme", required=True)
    resolve.add_argument("--field", choices=("products", "xctestrun"), required=True)

    suites = subparsers.add_parser("suites")
    suites.add_argument("--input", type=pathlib.Path, required=True)
    suites.add_argument("--output", type=pathlib.Path, required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    try:
        if args.command == "create":
            manifest = create_manifest(args.root, args.scheme)
            print(f"Created {args.root / 'manifest.json'} for {len(manifest['schemes'])} schemes")
        elif args.command == "resolve":
            print(resolved_path(args.root, args.scheme, args.field))
        elif args.command == "suites":
            suites = suite_identifiers(json.loads(args.input.read_text()))
            if not suites:
                raise ValueError("test enumeration contained no suites")
            args.output.write_text("".join(f"{suite}\n" for suite in suites))
            print(f"Wrote {len(suites)} suites to {args.output}")
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
