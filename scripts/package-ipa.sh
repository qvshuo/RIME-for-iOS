#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 暂存、校验完成后再替换产物，打包失败不损坏上一份 IPA。
python3 - "$ROOT" "${1:-$ROOT/build/Release/Build/Products/Release-iphoneos/RIMEForiOS.app}" "${2:-}" <<'PYCODE'
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile

root, app = Path(sys.argv[1]), Path(sys.argv[2]).resolve()
extension = app / "PlugIns/RIMEKeyboard.appex"
main = plistlib.loads((app / "Info.plist").read_bytes())
keyboard = plistlib.loads((extension / "Info.plist").read_bytes())
version = main["CFBundleShortVersionString"]
for info, identifier in [(main, "art.anjing.rimeios"), (keyboard, "art.anjing.rimeios.keyboard")]:
    if info["CFBundleIdentifier"] != identifier:
        sys.exit(f"Unexpected bundle identifier: {info['CFBundleIdentifier']}")
    if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (version, main["CFBundleVersion"]):
        sys.exit("App and keyboard versions differ")
    if info["CFBundleSupportedPlatforms"] != ["iPhoneOS"]:
        sys.exit("Package a device build, not a simulator build")
if any(app.rglob("_CodeSignature")) or any(app.rglob("embedded.mobileprovision")):
    sys.exit("Expected an unsigned build")

output = Path(sys.argv[3]).resolve() if sys.argv[3] else root / f"build/RIME-for-iOS-{version}-unsigned.ipa"
output.parent.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix=".ipa-", dir=output.parent) as stage:
    stage = Path(stage)
    payload = stage / "Payload"
    payload.mkdir()
    shutil.copytree(app, payload / app.name, symlinks=True)
    archive = stage / "package.ipa"
    subprocess.run(["zip", "-rqy", "-X", str(archive), "Payload"], cwd=stage, check=True)
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            sys.exit("IPA integrity check failed")
    os.replace(archive, output)
print(f"Packaged {version} ({main['CFBundleVersion']}): {output}")
PYCODE
