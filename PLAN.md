# Build Pipeline Plan: Template + CI/CD Language Pack Embedding

## Background

Each script in this repo is designed as a standalone single-file download. Users run:

```bash
curl -sSL https://raw.githubusercontent.com/.../nvidia-install.sh | sudo bash
```

This means every script must be self-contained — no `source`, no external dependencies. Language packs (~700 lines per script) are currently copy-pasted into each script manually, leading to:

- Duplicated translations across scripts
- Manual sync errors when updating translations
- Business logic buried under hundreds of lines of language pack data
- Painful workflow: edit `.pot` → run `language_pack_generate.py` → manually copy output into script

## Goal

Separate language packs from business logic at **development time**, automatically merge them at **build time**.

---

## Repository Structure

### Current

```
├── cuda-install.sh                    # Final script with embedded lang packs
├── nvidia-install.sh                  # Final script with embedded lang packs
├── nvidia-container-installer.sh
├── nvidia-container-uninstall.sh
├── nvidia-uninstall.sh
├── language_packs/
│   ├── ZH_CN.pot                      # nvidia-install.sh translations (source)
│   ├── ZH_CN.sh                       # nvidia-install.sh translations (generated)
│   ├── EN_US.pot
│   └── EN_US.sh
└── language_pack_generate.py          # .pot → .sh converter
```

### Proposed

```
├── src/                               # Template scripts (no embedded lang packs)
│   ├── nvidia-install.sh
│   ├── cuda-install.sh
│   ├── nvidia-container-installer.sh
│   ├── nvidia-container-uninstall.sh
│   └── nvidia-uninstall.sh
│
├── lang/                              # Language packs, organized by script
│   ├── nvidia-install/
│   │   ├── ZH_CN.sh
│   │   └── EN_US.sh
│   ├── cuda-install/
│   │   ├── ZH_CN.sh
│   │   └── EN_US.sh
│   ├── nvidia-container-installer/
│   │   ├── ZH_CN.sh
│   │   └── EN_US.sh
│   ├── nvidia-container-uninstall/
│   │   ├── ZH_CN.sh
│   │   └── EN_US.sh
│   └── nvidia-uninstall/
│       ├── ZH_CN.sh
│       └── EN_US.sh
│
├── scripts/
│   ├── build.py                       # Template + lang packs → final scripts
│   └── extract_keys.py                # Extract gettext keys from src/ for translation
│
├── dist/                              # Build output (gitignored)
│   ├── nvidia-install.sh
│   ├── cuda-install.sh
│   └── ...
│
├── .github/workflows/
│   └── release.yml                    # Auto-build on release
│
├── language_packs/                    # Deprecated, migrated to lang/
├── language_pack_generate.py          # Deprecated, replaced by scripts/build.py
└── PLAN.md
```

---

## Template Format

### Placeholder in `src/*.sh`

Each template script contains a single placeholder where language packs will be injected:

```bash
#!/bin/bash

set -eo pipefail

readonly SCRIPT_VERSION="2.2"

# Color definitions...
# Exit code definitions...
# Global variables...

# ================ Language Packs ==================
# {{LANG_PACKS}}
# ================ Language Packs End ==============

gettext() {
    local msgid="$1"
    local translation=""
    case "$LANG_CURRENT" in
        "zh-cn"|"zh"|"zh_CN") translation="${LANG_PACK_ZH_CN[$msgid]:-}" ;;
        "en-us"|"en"|"en_US") translation="${LANG_PACK_EN_US[$msgid]:-}" ;;
        *) translation="${LANG_PACK_ZH_CN[$msgid]:-}" ;;
    esac
    if [[ -z "$translation" ]]; then
        translation="$msgid"    # Fallback: return key itself
    fi
    printf '%s' "$translation"
}

# ... rest of business logic ...
```

### Language Pack Files (`lang/<script>/<LANG>.sh`)

Plain bash associative array declarations, one file per language per script:

```bash
# lang/cuda-install/ZH_CN.sh
declare -A LANG_PACK_ZH_CN

LANG_PACK_ZH_CN=(
    ["log.starting"]="开始执行 CUDA Toolkit 安装脚本"
    ["log.root_check.fail"]="此脚本需要 root 权限运行"
    # ...
)
```

---

## Build Script (`scripts/build.py`)

### Core Logic

```
For each src/<name>.sh:
  1. Read template content
  2. Find all lang/<name>/*.sh files
  3. Concatenate language pack contents
  4. Replace `# {{LANG_PACKS}}` with concatenated content
  5. Write to dist/<name>.sh
  6. chmod +x dist/<name>.sh
```

### CLI Interface

```bash
# Build all scripts
python3 scripts/build.py

# Build a specific script
python3 scripts/build.py --target cuda-install

# Build with specific languages only (e.g., for testing)
python3 scripts/build.py --langs ZH_CN,EN_US

# Output to custom directory
python3 scripts/build.py --outdir ./release
```

### Validation

The build script should also:

- Verify all `gettext` keys used in `src/*.sh` exist in every language pack
- Warn about unused keys in language packs
- Fail if any language pack has syntax errors (`bash -n`)
- Run `bash -n` on the final output

---

## GitHub Actions Workflow

### `.github/workflows/release.yml`

```yaml
name: Build and Release

on:
  release:
    types: [created]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.x'

      - name: Build scripts
        run: python3 scripts/build.py --outdir ./dist

      - name: Verify syntax
        run: |
          for f in dist/*.sh; do
            bash -n "$f"
            echo "✓ $f"
          done

      - name: Upload release assets
        uses: softprops/action-gh-release@v2
        with:
          files: dist/*.sh
```

### Separate CI workflow for PRs (`.github/workflows/ci.yml`)

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Build scripts
        run: python3 scripts/build.py

      - name: Syntax check
        run: |
          for f in dist/*.sh; do
            bash -n "$f"
          done

      - name: Verify translation completeness
        run: python3 scripts/build.py --check-keys
```

---

## Key Extraction Script (`scripts/extract_keys.py`)

Scans `src/*.sh` for all `gettext "..."` calls and outputs a list of required keys. This helps translators know what needs translating.

```bash
# Show all keys used in cuda-install.sh
python3 scripts/extract_keys.py src/cuda-install.sh

# Compare with existing language pack, show missing translations
python3 scripts/extract_keys.py src/cuda-install.sh --diff lang/cuda-install/EN_US.sh
```

---

## Developer Workflow

### Adding a new user-facing string

1. Add `$(gettext "new.key.name")` in `src/<script>.sh`
2. Add `["new.key.name"]="Translation"` to each `lang/<script>/<LANG>.sh`
3. Run `python3 scripts/build.py` to verify
4. Commit `src/` and `lang/` changes (not `dist/`)

### Adding a new language

1. Create `lang/<script>/<LANG>.sh` for each script (copy from existing and translate)
2. Update `gettext()` function in templates to recognize the new language code
3. Run `python3 scripts/build.py` — new language is automatically included

### Local testing

```bash
# Build and test locally
python3 scripts/build.py
sudo bash dist/nvidia-install.sh --help

# Or run template directly (works, but shows raw keys instead of translations)
sudo bash src/nvidia-install.sh --help
```

---

## Migration Steps

### Phase 1: Create build infrastructure

1. Create `scripts/build.py`
2. Create `scripts/extract_keys.py`
3. Add `dist/` to `.gitignore`

### Phase 2: Migrate scripts to templates

For each script:

1. Copy script to `src/<name>.sh`
2. Extract language pack section from `src/<name>.sh` to `lang/<name>/ZH_CN.sh` and `lang/<name>/EN_US.sh`
3. Replace extracted section with `# {{LANG_PACKS}}` placeholder
4. Run `python3 scripts/build.py` and verify `dist/<name>.sh` matches original

### Phase 3: Setup CI/CD

1. Create `.github/workflows/release.yml`
2. Create `.github/workflows/ci.yml`
3. Test with a pre-release

### Phase 4: Cleanup

1. Remove root-level script files (they now live in `src/`)
2. Remove old `language_packs/` directory
3. Remove old `language_pack_generate.py`
4. Update `README.md` with new development workflow
5. Update raw download URLs in documentation to point to release assets instead of raw repo files

### Phase 5: README URL migration

The download instructions currently point to raw repo files:

```bash
# Before (points to repo, which will now be a template)
curl -sSL https://raw.githubusercontent.com/.../main/nvidia-install.sh

# After (points to latest release asset)
curl -sSL https://github.com/.../releases/latest/download/nvidia-install.sh
```

---

## Considerations

### Backward compatibility

- Existing users may have bookmarked raw GitHub URLs
- Keep root-level scripts for one release cycle as a transitional measure, or add a redirect/notice

### Fallback behavior

The `gettext()` function already returns the raw key when no translation is found. This means:

- Templates are runnable without building (just with raw keys shown)
- Missing translations degrade gracefully
- New keys don't break existing language packs

### Build reproducibility

- `scripts/build.py` should be deterministic (same input → same output)
- Consider embedding a build timestamp or commit hash in the output for traceability:
  ```bash
  # Auto-generated from template. Do not edit directly.
  # Build: 2026-02-17T12:00:00Z (commit abc1234)
  ```

---

## GPU PCI Device ID Database Automation

### Problem

`nvidia-install.sh` maintains a hand-curated database of ~294 NVIDIA GPU PCI device IDs across 7 architectures (Maxwell → Blackwell) in `init_gpu_database()`. This database is used to determine:

- GPU architecture (for open vs proprietary kernel module selection)
- Whether a detected GPU is known/supported

Manual maintenance has issues:

- New GPUs are released regularly — database quickly becomes stale
- Missing IDs cause false "Unknown" architecture detection, leading to wrong module selection
- No systematic way to verify completeness against real-world device IDs

### Data Source

The [PCI ID Repository](https://pci-ids.ucw.cz/) (also mirrored at [pciutils/pciids](https://github.com/pciutils/pciids)) maintains a comprehensive database of all PCI devices. NVIDIA is vendor `10de` with **800+** device entries.

Key insight: NVIDIA device names in pci.ids **consistently contain chip code prefixes** that directly map to architectures:

| Chip Code Prefix | Architecture | Open Module Support |
|---|---|---|
| GK | Kepler | No (EOL) |
| GM | Maxwell | No |
| GP | Pascal | No |
| GV | Volta | No |
| TU | Turing | Yes |
| GA | Ampere | Yes |
| GH | Hopper | Yes (datacenter) |
| AD | Ada Lovelace | Yes |
| GB | Blackwell | Yes |

Example entries from pci.ids:
```
1b80  GP104 [GeForce GTX 1080]       → prefix GP → Pascal
2204  GA102 [GeForce RTX 3090]       → prefix GA → Ampere
2684  AD102 [GeForce RTX 4090]       → prefix AD → Ada Lovelace
```

### Proposed Solution

#### 1. External Data File (`data/gpu-ids.sh`)

Extract the GPU ID database from the script into a standalone data file:

```bash
# data/gpu-ids.sh
# Auto-generated from pci.ids — do not edit manually
# Source: https://pci-ids.ucw.cz/
# Generated: 2026-02-17T12:00:00Z
# Total IDs: 450+

GPU_IDS_MAXWELL=("1340" "1341" "1344" ... )
GPU_IDS_PASCAL=("15f7" "15f8" "15f9" ... )
GPU_IDS_VOLTA=("1db0" "1db1" ... )
GPU_IDS_TURING=("1e02" "1e04" ... )
GPU_IDS_AMPERE=("2204" "2205" ... )
GPU_IDS_HOPPER=("2321" "2322" ... )
GPU_IDS_ADA=("2684" "2685" ... )
GPU_IDS_BLACKWELL=("2330" "2331" ... )
```

#### 2. Generator Script (`scripts/update_gpu_ids.py`)

```python
#!/usr/bin/env python3
"""
Fetch NVIDIA GPU PCI device IDs from pci-ids.ucw.cz
and generate data/gpu-ids.sh with architecture mapping.
"""

# Core logic:
# 1. Download https://pci-ids.ucw.cz/v2.2/pci.ids (or GitHub mirror)
# 2. Parse vendor 10de section
# 3. For each device entry, extract chip code from device name
#    (regex: r'\b(GK|GM|GP|GV|TU|GA|GH|AD|GB)\d{2,3}\b')
# 4. Map chip code prefix → architecture
# 5. Generate data/gpu-ids.sh

CHIP_TO_ARCH = {
    "GK": "Kepler",
    "GM": "Maxwell",
    "GP": "Pascal",
    "GV": "Volta",
    "TU": "Turing",
    "GA": "Ampere",
    "GH": "Hopper",
    "AD": "Ada Lovelace",
    "GB": "Blackwell",
}

# Entries without chip codes (audio controllers, USB, bridges)
# are filtered out — only GPU/compute devices are included.
```

#### 3. Build Integration

The `scripts/build.py` pipeline embeds `data/gpu-ids.sh` into `nvidia-install.sh` during build, similar to language packs:

```bash
# In src/nvidia-install.sh template:
# ================ GPU ID Database ==================
# {{GPU_IDS}}
# ================ GPU ID Database End ==============
```

#### 4. CI Automation (`.github/workflows/update-gpu-ids.yml`)

```yaml
name: Update GPU ID Database

on:
  schedule:
    - cron: '0 0 * * 1'  # Weekly on Monday
  workflow_dispatch:       # Manual trigger

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate GPU ID database
        run: python3 scripts/update_gpu_ids.py

      - name: Check for changes
        id: diff
        run: |
          if git diff --quiet data/gpu-ids.sh; then
            echo "changed=false" >> $GITHUB_OUTPUT
          else
            echo "changed=true" >> $GITHUB_OUTPUT
          fi

      - name: Create PR if changed
        if: steps.diff.outputs.changed == 'true'
        uses: peter-evans/create-pull-request@v6
        with:
          title: "chore: update GPU PCI device ID database"
          body: |
            Auto-generated from [pci-ids.ucw.cz](https://pci-ids.ucw.cz/).
            Please review the diff for new GPU architecture entries.
          branch: auto/update-gpu-ids
          commit-message: "chore: update GPU PCI device ID database"
```

This runs weekly, compares against the existing `data/gpu-ids.sh`, and opens a PR if new device IDs are found — keeping humans in the loop for review.

#### 5. Fallback Strategy

- If a device ID is not in the database at all, the script already falls back to `"Unknown"` architecture
- Unknown architecture defaults to attempting open kernel module first (safe default for Turing+)
- The database should also include a **manually curated override section** at the bottom of `data/gpu-ids.sh` for entries that pci.ids gets wrong or hasn't added yet

### Updated Repository Structure

```
├── src/                               # Template scripts
├── lang/                              # Language packs
├── data/                              # Generated data files
│   └── gpu-ids.sh                     # GPU PCI device ID → architecture mapping
├── scripts/
│   ├── build.py                       # Template + lang + data → final scripts
│   ├── extract_keys.py                # Gettext key extraction
│   └── update_gpu_ids.py              # Fetch & generate GPU ID database
├── dist/                              # Build output (gitignored)
└── .github/workflows/
    ├── release.yml                    # Build on release
    ├── ci.yml                         # PR validation
    └── update-gpu-ids.yml             # Weekly GPU ID update
```

### Migration

1. Create `scripts/update_gpu_ids.py` and run it to generate `data/gpu-ids.sh`
2. Verify generated data matches/exceeds current hand-curated database
3. Add `# {{GPU_IDS}}` placeholder to `src/nvidia-install.sh`
4. Update `scripts/build.py` to embed `data/gpu-ids.sh`
5. Add `update-gpu-ids.yml` workflow
6. Remove hand-curated `init_gpu_database()` content from template
