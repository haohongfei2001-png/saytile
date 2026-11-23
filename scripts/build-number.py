#!/usr/bin/env python3
"""A curated release history must not reset Sparkle's monotonic build version."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
value = (root / 'packaging/BUILD_NUMBER').read_text().strip()
if not value.isascii() or not value.isdecimal() or int(value) <= 0 or str(int(value)) != value:
    raise SystemExit('packaging/BUILD_NUMBER must be a canonical positive integer')
print(value)
