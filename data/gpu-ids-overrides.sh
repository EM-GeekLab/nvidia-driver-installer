# Manual GPU device ID overrides
# These IDs are not yet in the pci-ids.ucw.cz database but are known from
# NVIDIA documentation or hardware testing.
#
# Format: # OVERRIDE: <device_id> = <Architecture>
# These are merged into data/gpu-ids.sh by scripts/update_gpu_ids.py

# Turing (TU1xx) - not yet in pci.ids
# OVERRIDE: 1ffa = Turing
# OVERRIDE: 1ffb = Turing
# OVERRIDE: 1ffc = Turing
# OVERRIDE: 1ffd = Turing
# OVERRIDE: 1fff = Turing

# Ampere (GA1xx) - not yet in pci.ids
# OVERRIDE: 2545 = Ampere
# OVERRIDE: 2548 = Ampere
# OVERRIDE: 254b = Ampere
# OVERRIDE: 25fc = Ampere

# Ada Lovelace (AD1xx) - not yet in pci.ids
# OVERRIDE: 2688 = Ada Lovelace
# OVERRIDE: 268a = Ada Lovelace
# OVERRIDE: 268b = Ada Lovelace
# OVERRIDE: 268e = Ada Lovelace
# OVERRIDE: 268f = Ada Lovelace
# OVERRIDE: 2706 = Ada Lovelace
# OVERRIDE: 2708 = Ada Lovelace
# OVERRIDE: 270a = Ada Lovelace
# OVERRIDE: 270b = Ada Lovelace
# OVERRIDE: 270d = Ada Lovelace
# OVERRIDE: 270f = Ada Lovelace
# OVERRIDE: 2718 = Ada Lovelace
# OVERRIDE: 2760 = Ada Lovelace
# OVERRIDE: 2887 = Ada Lovelace
# OVERRIDE: 2888 = Ada Lovelace
# OVERRIDE: 28bc = Ada Lovelace
