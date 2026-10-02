#!/usr/bin/env python
"""Compile every Luau file the way Roblox Studio does, so a script that cannot load never ships.

stylua, selene and luau-lsp do not compile. Studio compiles with full debug info (-g2), where
every local keeps its own register, including constants that a release build folds away. Luau
allows 200 locals per function, and a module's top level is one function, so a big controller
can pass every other check and still fail in Studio with "Out of local registers" (P3, 2026-10-02:
InputController and AbilityFx).

The compiler is the official luau-compile from the pinned Luau release. Rokit cannot install it
(it maps any alias of luau-lang/luau to the interpreter), so the first run downloads the release
zip into tools/bin/ (gitignored).

Usage:
  py tools/check_compile.py            # compile src/**/*.luau; exit 1 on any compile error
  py tools/check_compile.py --counts   # also list the files with the most top-level locals
"""

from __future__ import annotations

import argparse
import io
import platform
import re
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "src"
BIN_DIR = ROOT / "tools" / "bin"
LUAU_VERSION = "0.740"
RELEASE_URL = "https://github.com/luau-lang/luau/releases/download/{version}/{asset}"
ASSETS = {"Windows": "luau-windows.zip", "Darwin": "luau-macos.zip", "Linux": "luau-ubuntu.zip"}
# Studio's settings: optimisation 1, debug level 2 (locals are never folded away).
STUDIO_FLAGS = ["--null", "-O1", "-g2"]
# The compiler's hard limit, and the estimate above which this check fails early. The margin
# keeps a file from passing today and breaking on the next constant someone adds.
LOCAL_LIMIT = 200
LOCAL_BUDGET = 180
FILES_PER_CALL = 40

LOCAL_FUNCTION = re.compile(r"local function\s+\w+")
LOCAL_NAMES = re.compile(r"local\s+([^=]+?)\s*(=|$)")
TYPE_ANNOTATION = re.compile(r":[^,]+")


def compiler_path() -> Path:
    name = "luau-compile.exe" if platform.system() == "Windows" else "luau-compile"
    return BIN_DIR / name


def ensure_compiler() -> Path:
    path = compiler_path()
    if path.exists():
        return path
    asset = ASSETS.get(platform.system())
    if asset is None:
        sys.exit(f"check_compile: no Luau release asset for {platform.system()}")
    url = RELEASE_URL.format(version=LUAU_VERSION, asset=asset)
    print(f"downloading luau-compile {LUAU_VERSION} from {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    BIN_DIR.mkdir(parents=True, exist_ok=True)
    path.write_bytes(archive.read(path.name))
    path.chmod(0o755)
    return path


def top_level_locals(path: Path) -> int:
    """Estimate of the registers the module's top level needs: one per declared name."""
    count = 0
    for line in path.read_text(encoding="utf-8").splitlines():
        if LOCAL_FUNCTION.match(line):
            count += 1
            continue
        match = LOCAL_NAMES.match(line)
        if match is not None:
            names = TYPE_ANNOTATION.sub("", match.group(1))
            count += len([name for name in names.split(",") if name.strip()])
    return count


def compile_errors(compiler: Path, files: list[Path]) -> list[str]:
    errors: list[str] = []
    for start in range(0, len(files), FILES_PER_CALL):
        batch = [str(path.relative_to(ROOT)) for path in files[start : start + FILES_PER_CALL]]
        result = subprocess.run(
            [str(compiler), *STUDIO_FLAGS, *batch],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        for line in (result.stdout + result.stderr).splitlines():
            if "Error" in line:
                errors.append(line.strip())
    return errors


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--counts", action="store_true", help="list the largest top levels")
    args = parser.parse_args()

    files = sorted(SOURCE.rglob("*.luau"))
    problems = compile_errors(ensure_compiler(), files)
    counts = sorted(((top_level_locals(path), path) for path in files), reverse=True)
    for count, path in counts:
        if count > LOCAL_BUDGET:
            problems.append(
                f"{path.relative_to(ROOT)}: about {count} top-level locals, over the budget of "
                f"{LOCAL_BUDGET} (Studio's limit is {LOCAL_LIMIT}); group constants or state "
                "into tables, or split the module"
            )
    if args.counts:
        for count, path in counts[:10]:
            print(f"{count:4d}  {path.relative_to(ROOT)}")
    for problem in problems:
        print(problem)
    if problems:
        sys.exit(f"CHECK: FAIL -- {len(problems)} problem(s) in {len(files)} files")
    print(f"CHECK: PASS -- {len(files)} files compile with Studio settings (-O1 -g2)")


if __name__ == "__main__":
    main()
