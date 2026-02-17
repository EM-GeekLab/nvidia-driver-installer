#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Fetch NVIDIA GPU PCI device IDs from pci-ids.ucw.cz and generate
data/gpu-ids.sh with architecture mapping.

The PCI ID Repository maintains a comprehensive database of all PCI devices.
NVIDIA device names consistently contain chip code prefixes (e.g., "GP104",
"GA102", "AD102") that directly map to GPU architectures.

Usage:
    python3 scripts/update_gpu_ids.py                  # Generate data/gpu-ids.sh
    python3 scripts/update_gpu_ids.py --dry-run        # Show what would be generated
    python3 scripts/update_gpu_ids.py --stats          # Show statistics only
    python3 scripts/update_gpu_ids.py --source ucw     # Use ucw.cz instead of GitHub mirror
"""

from __future__ import annotations

import argparse
import re
import sys
import urllib.request
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
OUTPUT_FILE = DATA_DIR / "gpu-ids.sh"
OVERRIDES_FILE = DATA_DIR / "gpu-ids-overrides.sh"

# PCI IDs data sources
SOURCES = {
    "ucw": "https://pci-ids.ucw.cz/v2.2/pci.ids",
    "github": "https://raw.githubusercontent.com/pciutils/pciids/master/pci.ids",
}

NVIDIA_VENDOR_ID = "10de"

# Regex to validate a 4-character hex PCI device ID
DEVICE_ID_RE = re.compile(r"^[0-9a-f]{4}$")

# Chip code prefix → Architecture mapping
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

# Architecture → open kernel module support
ARCH_OPEN_MODULE = {
    "Kepler": False,
    "Maxwell": False,
    "Pascal": False,
    "Volta": False,
    "Turing": True,
    "Ampere": True,
    "Hopper": True,
    "Ada Lovelace": True,
    "Blackwell": True,
}

# Chip code regex: matches prefixes like GM107, GP104, TU102, GA102, AD102, GB202
CHIP_CODE_RE = re.compile(r"\b(GK|GM|GP|GV|TU|GA|GH|AD|GB)\d{2,3}")

# Filter: skip non-GPU devices (audio controllers, USB controllers, bridges, etc.)
# Uses regex word boundaries to avoid false positives (e.g., "PCIe" matching "PCI")
NON_GPU_PATTERNS = [
    r"\bHigh Definition Audio\b",
    r"\bUSB\b",
    r"\bBridge\b",
    r"\bXHCI\b",
    r"\bUCSI\b",
    r"\bSMBus\b",
    r"\bSerial\b",
    r"\bnForce\b",
    r"\bMCP\d",
    r"\bCK8\b",
    r"\bISA\b",
    r"\bIDE\b",
    r"\bSATA\b",
    r"\bPCI(?!e)\b",  # Match "PCI" but not "PCIe"
    r"\bEthernet\b",
    r"\bNetwork\b",
]
_NON_GPU_RE = re.compile("|".join(NON_GPU_PATTERNS), re.IGNORECASE)


def fetch_pci_ids(source: str = "github") -> str:
    """Download the pci.ids database."""
    url = SOURCES.get(source, source)
    if not url.startswith("https://"):
        raise ValueError(f"Refusing to fetch from non-HTTPS URL: {url}")
    print(f"Fetching PCI IDs from {url}...")

    req = urllib.request.Request(url, headers={"User-Agent": "nvidia-driver-installer/update_gpu_ids"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = resp.read().decode("utf-8", errors="replace")

    print(f"Downloaded {len(data)} bytes")
    return data


def parse_nvidia_devices(pci_ids_content: str) -> list[tuple[str, str]]:
    """Parse NVIDIA devices from pci.ids content.

    Returns list of (device_id, device_name) tuples.
    """
    devices = []
    in_nvidia = False

    for line in pci_ids_content.splitlines():
        # Skip comments and empty lines
        if not line or line.startswith("#"):
            continue

        # Vendor line: no leading whitespace
        if not line[0].isspace():
            parts = line.split(None, 1)
            if len(parts) >= 2 and parts[0].lower() == NVIDIA_VENDOR_ID:
                in_nvidia = True
                continue
            elif in_nvidia:
                # We've left the NVIDIA section
                break
            continue

        if not in_nvidia:
            continue

        # Device line: single tab indent
        if line.startswith("\t") and not line.startswith("\t\t"):
            parts = line.strip().split(None, 1)
            if len(parts) >= 2:
                device_id = parts[0].lower()
                device_name = parts[1]
                if not DEVICE_ID_RE.match(device_id):
                    print(f"Warning: skipping invalid device ID '{device_id}' ({device_name})", file=sys.stderr)
                    continue
                devices.append((device_id, device_name))

    return devices


def classify_device(device_id: str, device_name: str) -> str | None:
    """Classify a device into an architecture based on chip code in its name.

    Returns architecture name or None if not a GPU device.
    """
    # Filter out non-GPU devices
    if _NON_GPU_RE.search(device_name):
        return None

    # Extract chip code
    match = CHIP_CODE_RE.search(device_name)
    if not match:
        return None

    prefix = match.group(1)
    return CHIP_TO_ARCH.get(prefix)


def load_overrides() -> dict[str, str]:
    """Load manual overrides from data/gpu-ids-overrides.sh if it exists."""
    overrides = {}
    if not OVERRIDES_FILE.exists():
        return overrides

    content = OVERRIDES_FILE.read_text(encoding="utf-8")
    # Parse lines like: # OVERRIDE: 1234 = Architecture
    for match in re.finditer(r"#\s*OVERRIDE:\s*([0-9a-fA-F]{4})\s*=\s*(.+)", content):
        device_id = match.group(1).lower()
        arch = match.group(2).strip()
        overrides[device_id] = arch

    return overrides


def generate_gpu_ids_sh(arch_devices: dict[str, list[str]], total_pci_devices: int, source: str = "github") -> str:
    """Generate the data/gpu-ids.sh file content."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    total_ids = sum(len(ids) for ids in arch_devices.values())
    source_url = SOURCES.get(source, source)

    lines = [
        "# GPU Architecture Detection Database",
        "# Auto-generated by scripts/update_gpu_ids.py - do not edit manually",
        f"# Source: {source_url} (vendor {NVIDIA_VENDOR_ID})",
        f"# Generated: {now}",
        f"# Total GPU IDs: {total_ids} (from {total_pci_devices} NVIDIA PCI entries)",
        "#",
        "# To add manual overrides, edit data/gpu-ids-overrides.sh",
        "",
        "declare -A GPU_ARCH_DB",
        "",
        "# Initialize GPU architecture database",
        "init_gpu_database() {",
    ]

    # Ordered architectures (chronological)
    arch_order = ["Kepler", "Maxwell", "Pascal", "Volta", "Turing", "Ampere", "Hopper", "Ada Lovelace", "Blackwell"]

    for arch in arch_order:
        ids = arch_devices.get(arch, [])
        if not ids:
            continue

        open_module = ARCH_OPEN_MODULE.get(arch, False)
        module_note = "supports open kernel module" if open_module else "requires proprietary module"
        var_name = arch.lower().replace(" ", "_")

        lines.append(f"    # {arch} ({module_note})")
        # Format IDs in rows of 10
        id_strs = [f'"{id}"' for id in sorted(ids)]
        lines.append(f"    local {var_name}_ids=(")
        for i in range(0, len(id_strs), 10):
            chunk = " ".join(id_strs[i : i + 10])
            lines.append(f"        {chunk}")
        lines.append("    )")
        lines.append("")

    # Generate the assignment loops
    lines.append("    # Populate database")
    for arch in arch_order:
        if arch not in arch_devices:
            continue
        var_name = arch.lower().replace(" ", "_")
        lines.append(f'    for id in "${{{var_name}_ids[@]}}"; do')
        lines.append(f'        GPU_ARCH_DB["$id"]="{arch}"')
        lines.append("    done")
        lines.append("")

    lines.append("}")
    lines.append("")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch NVIDIA GPU PCI device IDs and generate architecture mapping"
    )
    parser.add_argument(
        "--source",
        choices=list(SOURCES.keys()),
        default="github",
        help="PCI IDs data source (default: github)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print output to stdout instead of writing to file",
    )
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Show statistics only, don't generate output",
    )
    parser.add_argument(
        "--output",
        help=f"Output file path (default: {OUTPUT_FILE})",
    )
    args = parser.parse_args()

    # Fetch PCI IDs
    try:
        pci_ids_content = fetch_pci_ids(args.source)
    except Exception as e:
        print(f"Error fetching PCI IDs: {e}", file=sys.stderr)
        sys.exit(1)

    # Parse NVIDIA devices
    devices = parse_nvidia_devices(pci_ids_content)
    print(f"Found {len(devices)} NVIDIA PCI device entries")

    # Classify into architectures
    arch_devices: dict[str, list[str]] = defaultdict(list)
    unclassified = []

    for device_id, device_name in devices:
        arch = classify_device(device_id, device_name)
        if arch:
            arch_devices[arch].append(device_id)
        else:
            unclassified.append((device_id, device_name))

    # Apply manual overrides
    overrides = load_overrides()
    for device_id, arch in overrides.items():
        if not DEVICE_ID_RE.match(device_id):
            print(f"Warning: skipping invalid override device ID '{device_id}'", file=sys.stderr)
            continue
        if arch in CHIP_TO_ARCH.values():
            arch_devices[arch].append(device_id)
            print(f"Override: {device_id} → {arch}")
        else:
            print(f"Warning: skipping override '{device_id}' with unknown architecture '{arch}'", file=sys.stderr)

    # Deduplicate
    for arch in arch_devices:
        arch_devices[arch] = sorted(set(arch_devices[arch]))

    # Statistics
    total_classified = sum(len(ids) for ids in arch_devices.values())
    print(f"\nClassified: {total_classified} GPU device IDs")
    print(f"Unclassified: {len(unclassified)} entries (non-GPU or unknown)")
    print()

    arch_order = ["Kepler", "Maxwell", "Pascal", "Volta", "Turing", "Ampere", "Hopper", "Ada Lovelace", "Blackwell"]
    for arch in arch_order:
        ids = arch_devices.get(arch, [])
        if ids:
            open_str = "open" if ARCH_OPEN_MODULE.get(arch) else "proprietary"
            print(f"  {arch:15s}: {len(ids):4d} IDs ({open_str})")

    if args.stats:
        return

    # Generate output
    output = generate_gpu_ids_sh(arch_devices, len(devices), args.source)

    if args.dry_run:
        print("\n" + "=" * 60)
        print(output)
        return

    # Write to file
    output_path = Path(args.output) if args.output else OUTPUT_FILE
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(output, encoding="utf-8")
    print(f"\nWritten to {output_path} ({len(output.splitlines())} lines)")


if __name__ == "__main__":
    main()
