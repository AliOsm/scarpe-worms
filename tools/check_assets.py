#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow>=10"]
# ///
"""Validate the assets consumed by the native game, without regenerating them.

    uv run tools/check_assets.py
    uv run tools/check_assets.py --output docs/validation/assets-0.4.0.json

Checks catalog coverage, animation canvases, clipping, terrain material alpha,
painted master provenance, PCM formats and distribution notices. Terrain/collision
agreement is exercised separately by test/terrain_art_test.rb.
"""
from __future__ import annotations

import argparse
import array
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import wave

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/art"
AUDIO = ROOT / "assets/audio"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, detail):
    if not condition:
        raise ValueError(detail)


def check_image(path, size, *, opaque=False, interior=False):
    require(path.is_file(), f"Missing image: {path.relative_to(ROOT)}")
    with Image.open(path) as im:
        require(im.size == size, f"Wrong size: {path.relative_to(ROOT)}: {im.size}, expected {size}")
        rgba = im.convert("RGBA")
        alpha = rgba.getchannel("A")
        require(alpha.getbbox() is not None, f"Empty image: {path}")
        if opaque:
            require(alpha.getextrema() == (255, 255), f"Unexpected transparency: {path}")
        if interior:
            left, top, right, bottom = alpha.point(lambda a: 255 if a > 12 else 0).getbbox()
            require(left > 0 and top > 0 and right < size[0] and bottom < size[1],
                    f"Sprite clips its canvas: {path.relative_to(ROOT)} {(left, top, right, bottom)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".cache/polish/assets.json")
    args = parser.parse_args()
    runtime = json.loads(subprocess.check_output([
        "bundle", "exec", "ruby", "-r", "./lib/burrow", "-r", "./lib/burrow/client/audio", "-e",
        "puts JSON.generate({weapons: Burrow::Catalog::WEAPONS.keys, cues: Burrow::Client::Audio::CUES})",
    ], cwd=ROOT, text=True))
    manifest = json.loads((ART / "manifest.json").read_text())
    require(set(runtime["weapons"]) == set(manifest["weapons"]["ids"]), "Weapon manifest/catalog mismatch")
    for weapon in runtime["weapons"]:
        check_image(ART / "weapons" / f"{weapon}.png", (128, 128))
    for weapon in manifest["combat"]["held"]:
        for direction in ("", "left/"):
            check_image(ART / "held" / f"{direction}{weapon}.png", (128, 128), interior=True)
    for weapon in manifest["combat"]["projectiles"]:
        check_image(ART / "projectiles" / f"{weapon}.png", (128, 128), interior=True)
    for effect in manifest["extras"]["fx_animations"].values():
        for frame in range(effect["frames"]):
            check_image(ART / effect["pattern"].format(frame=frame), tuple(effect["source_size"]))
    for prop in manifest["props"].values():
        check_image(ART / prop["path"], tuple(prop["size"]))

    sprite_count = 0
    for team in range(manifest["grubs"]["teams"]):
        for state, spec in manifest["grubs"]["states"].items():
            for direction in ("", "left/"):
                for frame in range(spec["frames"]):
                    path = ART / "grubs" / f"{direction}{team}-{state}-{frame}.png"
                    check_image(path, (160, 160), interior=True)
                    sprite_count += 1
        for pose in manifest["grubs"]["portraits"]["poses"]:
            check_image(ART / "grubs/portraits" / f"{team}-{pose}.png", (512, 512), interior=True)

    for biome in ("meadow", "desert", "glacier", "volcano"):
        for material in ("fill", "deep", "shade", "edge"):
            check_image(ART / "terrain" / f"{biome}-{material}.png", (512, 512), opaque=True)
        check_image(ART / "terrain" / f"{biome}-crust.png", (512, 20))
        check_image(ART / "terrain" / f"{biome}-tufts.png", (512, 12))
        for layer in ("masonry", "masonry-edge"):
            check_image(ART / "terrain" / f"{biome}-{layer}.png", (128, 64), opaque=True)
    check_image(ART / "terrain/girder.png", (32, 6), opaque=True)
    material_dir = ART / "source/materials"
    materials = json.loads((material_dir / "provenance.json").read_text())
    require({item["name"] for item in materials["assets"]} == {"meadow", "desert", "glacier", "volcano"},
            "Painted material provenance must cover every biome")
    for material in materials["assets"]:
        require(sha(material_dir / material["source"]) == material["sha256"],
                f"Material provenance mismatch: {material['name']}")
        require(bool(material["prompt"]), f"Missing material generation prompt: {material['name']}")
    require(manifest["terrain"]["fill_size"] == [512, 512], "Runtime terrain contract mismatch")

    painting_dir = ART / "source/paintings"
    paintings = json.loads((painting_dir / "provenance.json").read_text())
    require(len(paintings["assets"]) == 5, "Expected menu and four painted biomes")
    for painting in paintings["assets"]:
        source = painting_dir / painting["source"]
        require(sha(source) == painting["sha256"], f"Painting provenance mismatch: {source.name}")
        require(bool(painting["prompt"]), f"Missing generation prompt: {source.name}")
        check_image(ART / f"{painting['name']}.png", tuple(painting["output_size"]), opaque=True)
        require(manifest["backgrounds"][painting["name"]]["source_sha256"] == painting["sha256"],
                f"Runtime manifest has an old painting hash: {source.name}")

    audio_manifest = json.loads((AUDIO / "source/kenney/manifest.json").read_text())
    for cue in audio_manifest["cues"]:
        source = AUDIO / "source/kenney" / cue["master"]
        require(sha(source) == cue["master_sha256"], f"Audio master checksum mismatch: {cue['cue']}")
        require(sha(source) == sha(AUDIO / f"{cue['cue']}.wav"), f"Stale compiled audio: {cue['cue']}")
    audio_seconds = {}
    require(set(runtime["cues"]) == {p.stem for p in AUDIO.glob("*.wav")}, "Runtime audio cue coverage mismatch")
    for cue in runtime["cues"]:
        with wave.open(str(AUDIO / f"{cue}.wav")) as wav:
            require(wav.getnchannels() == (2 if cue == "music" else 1), f"Wrong positioning format: {cue}")
            require(wav.getsampwidth() == 2 and wav.getframerate() == 22050, f"Wrong PCM encoding: {cue}")
            pcm = array.array("h", wav.readframes(wav.getnframes()))
            require(pcm and max(abs(v) for v in pcm) < 32767, f"Empty or clipped audio: {cue}")
            audio_seconds[cue] = round(wav.getnframes() / wav.getframerate(), 3)
    require((AUDIO / "KENNEY-NOTICES.txt").is_file(), "Missing shipped sound notices")
    for font in ("Inter", "Fredoka", "FiraMono"):
        require((ROOT / "assets/fonts" / f"{font}-LICENSE").is_file(), f"Missing font license: {font}")

    runtime_pngs = [p for p in ART.rglob("*.png") if "source" not in p.relative_to(ART).parts]
    report = {
        "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "version": re.search(r'VERSION = "([^"]+)"', (ROOT / "lib/burrow.rb").read_text()).group(1),
        "art_version": manifest["version"],
        "weapons": len(runtime["weapons"]), "animation_frames": sprite_count,
        "directional_combat_sprites": len(manifest["combat"]["held"]) * 2 + len(manifest["combat"]["projectiles"]),
        "portraits": 12, "biomes": 4, "painting_sources_verified": 5,
        "material_sources_verified": len(materials["assets"]),
        "licensed_audio_masters_verified": len(audio_manifest["cues"]),
        "audio_seconds": audio_seconds,
        "runtime_png_count": len(runtime_pngs),
        "runtime_png_bytes": sum(p.stat().st_size for p in runtime_pngs),
        "result": "passed",
        "scope": "Asset structure, provenance and format checks; not a subjective art review or an audible listening test.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
