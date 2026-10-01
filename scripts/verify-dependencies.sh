#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIME_ROOT="${RIME_ROOT:-$ROOT/../librime}"

# 二进制哈希可在没有上游源码的 CI 验证；重编译时必须核对源码提交。
python3 - "$ROOT" "$RIME_ROOT" "${1:-}" <<'PYCODE'
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

root, sources, mode = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
if mode not in ("", "--sources", "--binaries", "--record"):
    sys.exit("usage: verify-dependencies.sh [--sources|--binaries|--record]")
manifest_path = root / "Frameworks/versions.json"
manifest = json.loads(manifest_path.read_text())
if mode != "--binaries":
    for relative, expected in manifest["sources"].items():
        actual = subprocess.check_output(
            ["git", "-C", str(sources / relative), "rev-parse", "HEAD"], text=True).strip()
        if actual != expected:
            sys.exit(f"source mismatch: {relative}: {actual}, expected {expected}")
    boost = (sources / "deps/boost-1.89.0/boost/version.hpp").read_text()
    if not re.search(r"#define BOOST_VERSION\s+108900\b", boost):
        sys.exit("Boost must be 1.89.0")
    lua = (sources / "plugins/librime-lua/thirdparty/lua5.4/lua.h").read_text()
    if not all(re.search(rf'#define LUA_VERSION_{name}\s+"{value}"', lua)
               for name, value in [("MAJOR", "5"), ("MINOR", "4"), ("RELEASE", "8")]):
        sys.exit("Lua must be 5.4.8")
if mode != "--sources":
    actual = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((root / "Frameworks").rglob("*.a"))}
    if mode == "--record":
        manifest["binaries"] = actual
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    elif actual != manifest["binaries"]:
        sys.exit("framework hashes differ; verify build provenance before recording")
print(f"Verified Squirrel {manifest['squirrel']} dependency baseline ({mode or 'sources + binaries'})")
PYCODE
