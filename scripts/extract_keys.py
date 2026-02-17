#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Extract gettext keys from shell script templates.

Scans src/*.sh for all gettext "..." calls and outputs a list of required
translation keys. Optionally compares against existing language packs to
find missing or unused translations.

Usage:
    python3 scripts/extract_keys.py src/cuda-install.sh
    python3 scripts/extract_keys.py src/cuda-install.sh --diff lang/cuda-install/EN_US.sh
    python3 scripts/extract_keys.py --all
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Reuse extraction logic from build.py to avoid duplication
from build import extract_gettext_keys, extract_lang_pack_keys

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"
LANG_DIR = PROJECT_ROOT / "lang"


def extract_keys_from_script(path: Path) -> list[str]:
    """Extract all gettext keys from a shell script, preserving order."""
    content = path.read_text(encoding="utf-8")
    return sorted(extract_gettext_keys(content))


def extract_keys_from_lang_pack(path: Path) -> list[str]:
    """Extract all keys defined in a language pack file."""
    content = path.read_text(encoding="utf-8")
    return sorted(extract_lang_pack_keys(content))


def show_keys(script_path: Path) -> None:
    """Print all gettext keys used in a script."""
    keys = extract_keys_from_script(script_path)
    print(f"# Keys in {script_path.name}: {len(keys)}")
    for key in keys:
        print(f"  {key}")


def show_diff(script_path: Path, lang_path: Path) -> bool:
    """Compare script keys with language pack keys. Returns True if complete."""
    script_keys = set(extract_keys_from_script(script_path))
    lang_keys = set(extract_keys_from_lang_pack(lang_path))

    missing = script_keys - lang_keys
    unused = lang_keys - script_keys

    print(f"# Comparing {script_path.name} vs {lang_path.name}")
    print(f"  Script keys: {len(script_keys)}")
    print(f"  Lang keys:   {len(lang_keys)}")

    if missing:
        print(f"\n  MISSING ({len(missing)} keys not translated):")
        for key in sorted(missing):
            print(f"    - {key}")

    if unused:
        print(f"\n  UNUSED ({len(unused)} keys in lang but not in script):")
        for key in sorted(unused):
            print(f"    ~ {key}")

    if not missing and not unused:
        print("  Status: COMPLETE (all keys match)")
        return True

    return not missing  # Only fail on missing, unused is just a warning


def show_all() -> None:
    """Show keys for all templates and diff against all lang packs."""
    templates = sorted(SRC_DIR.glob("*.sh"))
    for template in templates:
        script_name = template.stem
        keys = extract_keys_from_script(template)
        if not keys:
            continue

        print(f"\n{'=' * 60}")
        print(f"  {script_name}: {len(keys)} gettext keys")
        print(f"{'=' * 60}")

        lang_dir = LANG_DIR / script_name
        if lang_dir.exists():
            for lang_file in sorted(lang_dir.glob("*.sh")):
                show_diff(template, lang_file)
                print()
        else:
            print(f"  No lang packs found at {lang_dir}")
            for key in keys:
                print(f"    {key}")


def main():
    parser = argparse.ArgumentParser(
        description="Extract and analyze gettext keys from shell script templates"
    )
    parser.add_argument(
        "script",
        nargs="?",
        help="Path to a shell script template",
    )
    parser.add_argument(
        "--diff",
        help="Compare with a language pack file to find missing/unused keys",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Analyze all templates in src/ against all lang packs",
    )
    args = parser.parse_args()

    if args.all:
        show_all()
        return

    if not args.script:
        parser.error("either provide a script path or use --all")

    script_path = Path(args.script)
    if not script_path.exists():
        print(f"Error: {script_path} not found", file=sys.stderr)
        sys.exit(1)

    if args.diff:
        lang_path = Path(args.diff)
        if not lang_path.exists():
            print(f"Error: {lang_path} not found", file=sys.stderr)
            sys.exit(1)
        ok = show_diff(script_path, lang_path)
        sys.exit(0 if ok else 1)
    else:
        show_keys(script_path)


if __name__ == "__main__":
    main()
