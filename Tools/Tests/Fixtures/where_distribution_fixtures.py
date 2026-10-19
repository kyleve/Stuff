"""Where Development signing fixtures and fake processes; no real credentials or devices.

The fixed app, extension, and export names model Where/archive's contract.
Keep these expected values independent of the production command's implementation.
"""

from datetime import datetime
import plistlib
import zipfile


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
