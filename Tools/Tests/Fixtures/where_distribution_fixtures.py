"""Small signing fixtures and fake processes; no real credentials or devices."""

from datetime import datetime
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import zipfile


REPOSITORY = Path(__file__).resolve().parents[3]
SHA = "a" * 40
TARGET_NAMES = ("Where", "WhereWidgets", "WhereShareExtension")
BUNDLE_IDS = ("com.stuff.where.development", "com.stuff.where.development.widgets",
              "com.stuff.where.development.share")


def profile(index):
    digit = str(index + 1)
    return {
        "UUID": f"{digit * 8}-{digit * 4}-{digit * 4}-{digit * 4}-{digit * 12}",
        "TeamIdentifier": ["TESTTEAM01"],
        "ApplicationIdentifierPrefix": ["TESTTEAM01"],
        "ExpirationDate": datetime(2099, 1, 1),
        "ProvisionedDevices": ["fixture-device"],
        "Entitlements": {"get-task-allow": False,
                         "application-identifier": f"TESTTEAM01.{BUNDLE_IDS[index]}"},
    }


def write_profiles(directory, extension="plist"):
    directory.mkdir(parents=True, exist_ok=True)
    for index, target in enumerate(TARGET_NAMES):
        (directory / f"{target}.{extension}").write_bytes(plistlib.dumps(profile(index)))


def write_ipa(path, changes=None, omit=None):
    info = {"CFBundleIdentifier": BUNDLE_IDS[0], "CFBundleVersion": "1",
            "CFBundleShortVersionString": "0.9.2", "MinimumOSVersion": "27.0", "WhereAudience": "development",
            "WhereGitStatus": "clean", "WhereConfiguration": "Debug",
            "WhereSwiftOptimizationLevel": "-O", "WhereGitSHA": SHA[:12],
            "InstallerAppID": "where", "InstallerGitStatus": "clean", "InstallerGitSHA": SHA}
    info.update(changes or {})
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Where.app/Info.plist", plistlib.dumps(info))
        for bundle in ("Payload/Where.app", "Payload/Where.app/PlugIns/WhereWidgets.appex",
                       "Payload/Where.app/PlugIns/WhereShareExtension.appex"):
            for resource in ("embedded.mobileprovision", "_CodeSignature/CodeResources"):
                name = f"{bundle}/{resource}"
                if name != omit:
                    archive.writestr(name, b"fixture signing resource")


class ArchiveFixture:
    def __init__(self, temporary):
        self.root = Path(temporary) / "repository with spaces ü"
        self.bin = self.root / "fake bin"
        self.home = self.root / "fixture home"
        self.temporary = self.root / "runner temp"
        self.profiles = self.root / "input profiles"
        self.output = self.root / "output archive"
        self.log = self.root / "commands.jsonl"
        for directory in (self.bin, self.home, self.temporary):
            directory.mkdir(parents=True, exist_ok=True)
        for name in ("Where/archive", "Tools/where_signing.py", ".github/where-signing.sh"):
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPOSITORY / name, destination)
        write_profiles(self.profiles, "mobileprovision")
        for name in ("security", "mise", "openssl"):
            self.executable(self.bin / name, FAKE_TOOL)
        self.executable(self.root / "ide", FAKE_TOOL)

    def executable(self, path, body):
        path.write_text(f"#!{sys.executable}\n{body}")
        path.chmod(0o755)

    def environment(self, overrides=None):
        environment = {"PATH": f"{self.bin}:{Path(sys.executable).parent}:/usr/bin:/bin",
                       "HOME": str(self.home), "RUNNER_TEMP": str(self.temporary),
                       "TMPDIR": str(self.temporary), "TOOL_LOG": str(self.log),
                       "PYTHONDONTWRITEBYTECODE": "1"}
        environment.update(overrides or {})
        return environment

    def run(self, command, *arguments, overrides=None):
        return subprocess.run(["/bin/bash", str(self.root / command), *map(str, arguments)],
                              cwd=self.root, env=self.environment(overrides),
                              capture_output=True, text=True)

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []


FAKE_TOOL = r'''
import json
import os
from pathlib import Path
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["TOOL_LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
action = args[0] if args else ""
if name == "mise":
    args = args[3:]
    action = args[0]
if os.environ.get("FAIL_AT") == f"{name}:{action}":
    print("fixture process failure", file=sys.stderr)
    sys.exit(47)
if name == "security":
    if action == "cms":
        sys.stdout.buffer.write(Path(args[args.index("-i") + 1]).read_bytes())
    elif action == "list-keychains" and "-s" not in args:
        print('"/fixture/login.keychain-db"')
    elif action == "create-keychain":
        Path(args[-1]).touch()
    elif action == "delete-keychain":
        Path(args[-1]).unlink()
elif name == "openssl":
    print("fixture-keychain-password")
elif name == "mise" and action == "-showBuildSettings":
    settings = []
    for target, suffix, key in (("Where", "", "APP"), ("WhereWidgets", ".widgets", "WIDGET"),
                                ("WhereShareExtension", ".share", "SHARE")):
        settings.append({"target": target, "buildSettings": {
            "PRODUCT_BUNDLE_IDENTIFIER": "wrong.bundle" if os.environ.get("WRONG_BUNDLE") else "com.stuff.where.development" + suffix,
            "DEVELOPMENT_TEAM": os.environ["TUIST_DEVELOPMENT_TEAM"],
            "PROVISIONING_PROFILE_SPECIFIER": os.environ[f"TUIST_WHERE_ADHOC_{key}_PROFILE"],
            "CODE_SIGN_STYLE": "Manual", "WHERE_AUDIENCE": "development"}})
    print(json.dumps(settings))
elif name == "mise" and action == "archive":
    Path(args[args.index("-archivePath") + 1]).mkdir()
elif name == "mise" and action == "-exportArchive":
    destination = Path(args[args.index("-exportPath") + 1])
    destination.mkdir()
    if not os.environ.get("MISSING_IPA"):
        (destination / "Where.ipa").write_bytes(b"fixture export")
'''
