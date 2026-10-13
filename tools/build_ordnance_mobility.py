"""Mobility: grapple, jetpack, parachute, teleport and girders attached to grubs.

Writes assets/art/ordnance/mobility/*.png and returns manifest metadata. Called by
`uv run tools/build_art.py ordnance`.
"""
from __future__ import annotations

from build_art_core import ART

OUT = ART / "ordnance" / "mobility"


def build_all():
    OUT.mkdir(parents=True, exist_ok=True)
    return {}


def metadata():
    """Static description of this family's sprites for the manifest (same whether or not it was rebuilt)."""
    return {}
