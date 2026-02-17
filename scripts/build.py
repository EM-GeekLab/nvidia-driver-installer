#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build pipeline: Merge template scripts with language packs and data files.

Reads src/*.sh templates, finds corresponding lang/<name>/*.sh language packs
and data files (e.g., data/gpu-ids.sh), replaces placeholders, and writes
final self-contained scripts to dist/.

Usage:
    python3 scripts/build.py                     # Build all scripts
    python3 scripts/build.py --target cuda-install  # Build specific script
    python3 scripts/build.py --langs ZH_CN,EN_US    # Specific languages only
    python3 scripts/build.py --outdir ./release      # Custom output directory
    python3 scripts/build.py --check-keys            # Verify translation completeness
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path


# Resolve project root (parent of scripts/)
PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC_DIR = PROJECT_ROOT / "src"
LANG_DIR = PROJECT_ROOT / "lang"
DATA_DIR = PROJECT_ROOT / "data"
DEFAULT_DIST_DIR = PROJECT_ROOT / "dist"

LANG_PACKS_PLACEHOLDER = "# {{LANG_PACKS}}"
GPU_IDS_PLACEHOLDER = "# {{GPU_IDS}}"


def find_templates(target: str | None = None) -> list[Path]:
    """Find template scripts in src/."""
    if target:
        path = SRC_DIR / f"{target}.sh"
        if not path.exists():
            print(f"Error: template not found: {path}", file=sys.stderr)
            sys.exit(1)
        return [path]
    templates = sorted(SRC_DIR.glob("*.sh"))
    if not templates:
        print(f"Error: no templates found in {SRC_DIR}", file=sys.stderr)
        sys.exit(1)
    return templates


def find_lang_packs(script_name: str, langs: list[str] | None = None) -> list[Path]:
    """Find language pack files for a given script."""
    lang_dir = LANG_DIR / script_name
    if not lang_dir.exists():
        return []
    packs = sorted(lang_dir.glob("*.sh"))
    if langs:
        packs = [p for p in packs if p.stem in langs]
    return packs


def find_data_file(filename: str) -> Path | None:
    """Find a data file (e.g., gpu-ids.sh)."""
    path = DATA_DIR / filename
    return path if path.exists() else None


def read_file(path: Path) -> str:
    """Read a file and return its content."""
    return path.read_text(encoding="utf-8")


def extract_gettext_keys(template_content: str) -> set[str]:
    """Extract all gettext key references from a template script.

    Handles both literal keys (gettext "key") and dynamic keys annotated with
    # GETTEXT_DYNAMIC: key1 key2 key3
    """
    keys = set()
    for match in re.finditer(r'gettext\s+"([^"]+)"', template_content):
        key = match.group(1)
        if not key.startswith("$"):
            keys.add(key)
    for match in re.finditer(r"gettext\s+'([^']+)'", template_content):
        key = match.group(1)
        if not key.startswith("$"):
            keys.add(key)
    # Support dynamic key annotations: # GETTEXT_DYNAMIC: key1 key2 ...
    for match in re.finditer(r"#\s*GETTEXT_DYNAMIC:\s*(.+)", template_content):
        for key in match.group(1).split():
            keys.add(key.strip())
    return keys


def extract_lang_pack_keys(lang_content: str) -> set[str]:
    """Extract all keys defined in a language pack file."""
    keys = set()
    for match in re.finditer(r'\["([^"]+)"\]', lang_content):
        keys.add(match.group(1))
    return keys


def check_keys(templates: list[Path], langs: list[str] | None = None) -> bool:
    """Check that all gettext keys in templates have translations in every language pack."""
    all_ok = True

    for template_path in templates:
        script_name = template_path.stem
        template_content = read_file(template_path)
        required_keys = extract_gettext_keys(template_content)

        if not required_keys:
            continue

        lang_packs = find_lang_packs(script_name, langs)
        if not lang_packs:
            print(f"Warning: {script_name} uses gettext but has no language packs")
            continue

        for pack_path in lang_packs:
            pack_content = read_file(pack_path)
            pack_keys = extract_lang_pack_keys(pack_content)

            missing = required_keys - pack_keys
            unused = pack_keys - required_keys

            if missing:
                all_ok = False
                print(f"Error: {script_name}/{pack_path.name}: {len(missing)} missing keys:")
                for key in sorted(missing):
                    print(f"  - {key}")

            if unused:
                print(f"Warning: {script_name}/{pack_path.name}: {len(unused)} unused keys:")
                for key in sorted(unused):
                    print(f"  ~ {key}")

    return all_ok


def validate_syntax(path: Path) -> bool:
    """Run bash -n to check syntax."""
    result = subprocess.run(
        ["bash", "-n", str(path)],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Syntax error in {path}:", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        return False
    return True


def build_script(
    template_path: Path,
    outdir: Path,
    langs: list[str] | None = None,
    skip_syntax_check: bool = False,
) -> bool:
    """Build a single script by merging template with language packs and data."""
    script_name = template_path.stem
    template_content = read_file(template_path)
    outdir.mkdir(parents=True, exist_ok=True)

    # --- Language Packs ---
    if LANG_PACKS_PLACEHOLDER in template_content:
        lang_packs = find_lang_packs(script_name, langs)
        if lang_packs:
            lang_content = "\n".join(read_file(p) for p in lang_packs)
            # Validate each lang pack syntax
            if not skip_syntax_check:
                for pack_path in lang_packs:
                    # Wrap in a function to make it parseable
                    test_script = f"#!/bin/bash\n{read_file(pack_path)}\n"
                    test_file = outdir / f".syntax_test_{pack_path.name}"
                    test_file.write_text(test_script, encoding="utf-8")
                    if not validate_syntax(test_file):
                        test_file.unlink(missing_ok=True)
                        return False
                    test_file.unlink(missing_ok=True)
        else:
            lang_content = "# No language packs found"
            print(f"Warning: {script_name} has {{{{LANG_PACKS}}}} placeholder but no lang packs in lang/{script_name}/")

        template_content = template_content.replace(LANG_PACKS_PLACEHOLDER, lang_content)

    # --- GPU IDs ---
    if GPU_IDS_PLACEHOLDER in template_content:
        gpu_ids_file = find_data_file("gpu-ids.sh")
        if gpu_ids_file:
            gpu_content = read_file(gpu_ids_file)
        else:
            gpu_content = "# No GPU ID database found"
            print(f"Warning: {script_name} has {{{{GPU_IDS}}}} placeholder but data/gpu-ids.sh not found")

        template_content = template_content.replace(GPU_IDS_PLACEHOLDER, gpu_content)

    # --- Write to temp file, validate, then rename ---
    output_path = outdir / f"{script_name}.sh"
    temp_path = outdir / f".{script_name}.sh.tmp"
    temp_path.write_text(template_content, encoding="utf-8")
    temp_path.chmod(0o755)

    # --- Syntax check before finalizing ---
    if not skip_syntax_check:
        if not validate_syntax(temp_path):
            temp_path.unlink(missing_ok=True)
            return False

    temp_path.rename(output_path)
    print(f"  Built: {output_path} ({len(template_content.splitlines())} lines)")
    return True


def main():
    parser = argparse.ArgumentParser(
        description="Build self-contained scripts from templates + language packs"
    )
    parser.add_argument(
        "--target",
        help="Build a specific script (e.g., cuda-install)",
    )
    parser.add_argument(
        "--langs",
        help="Comma-separated list of languages to include (e.g., ZH_CN,EN_US)",
    )
    parser.add_argument(
        "--outdir",
        default=str(DEFAULT_DIST_DIR),
        help=f"Output directory (default: {DEFAULT_DIST_DIR})",
    )
    parser.add_argument(
        "--check-keys",
        action="store_true",
        help="Check translation key completeness and exit",
    )
    parser.add_argument(
        "--skip-syntax-check",
        action="store_true",
        help="Skip bash -n syntax validation",
    )
    args = parser.parse_args()

    langs = [lang.strip() for lang in args.langs.split(",")] if args.langs else None
    outdir = Path(args.outdir)

    templates = find_templates(args.target)

    # Key check mode
    if args.check_keys:
        ok = check_keys(templates, langs)
        sys.exit(0 if ok else 1)

    # Build mode
    print(f"Building {len(templates)} script(s) → {outdir}/")
    success = True
    for template_path in templates:
        if not build_script(template_path, outdir, langs, args.skip_syntax_check):
            success = False

    if success:
        print(f"Build complete: {len(templates)} script(s)")
    else:
        print("Build failed with errors", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
