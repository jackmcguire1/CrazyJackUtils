#!/usr/bin/env python3
"""Check the addon folder against its TOC, and optionally zip or install it.

WoW only loads the files the TOC lists, and says nothing about a listed file that
doesn't exist, so the check fails on either mismatch.

Usage:
  uv run tools/build.py                       # check only
  uv run tools/build.py --zip                 # also write dist/CrazyJackUtils.zip to share
  uv run tools/build.py --install "<WoW>/_forever_/Interface/AddOns"
"""
import argparse
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
NAME = "CrazyJackUtils"
ADDON = ROOT / NAME
TOC = ADDON / f"{NAME}.toc"
SKIP_FILES = {".gitkeep", ".DS_Store"}


def toc_files() -> list[str]:
    """Files the TOC loads, as forward-slash paths relative to the addon folder."""
    files = []
    for line in TOC.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    return files


def check() -> list[str]:
    listed = toc_files()
    on_disk = {path.relative_to(ADDON).as_posix() for path in ADDON.rglob("*.lua")}
    errors = [f"{TOC.name} lists {name}, which doesn't exist" for name in listed if not (ADDON / name).is_file()]
    errors += [f"{name} is listed twice in {TOC.name}" for name in sorted({n for n in listed if listed.count(n) > 1})]
    # Compared without case: WoW's file lookups ignore it, but a Linux checkout doesn't.
    lowered = {name.lower() for name in listed}
    errors += [f"{name} isn't listed in {TOC.name}, so WoW won't load it" for name in sorted(on_disk)
               if name.lower() not in lowered]
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", action="store_true", help=f"write dist/{NAME}.zip for sharing")
    parser.add_argument("--install", metavar="ADDONS_DIR", help="copy the addon into this Interface/AddOns folder")
    args = parser.parse_args()

    errors = check()
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    if errors:
        return 1
    print(f"{TOC.name} lists {len(toc_files())} files, all present")

    if args.zip:
        dist = ROOT / "dist"
        dist.mkdir(exist_ok=True)
        archive = dist / f"{NAME}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            for path in sorted(ADDON.rglob("*")):
                if path.is_file() and path.name not in SKIP_FILES:
                    zf.write(path, path.relative_to(ROOT))
        print(f"Wrote {archive.relative_to(ROOT)}")

    if args.install:
        target = Path(args.install).expanduser() / NAME
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ADDON, target, ignore=shutil.ignore_patterns(*SKIP_FILES))
        print(f"Installed to {target}")
        print("/reload picks up changed files; restart WoW after adding new ones.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
