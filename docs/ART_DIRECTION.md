# BURROW BRIGADE: Art Direction & Asset Guide

All art lives in `assets/art/`. Characters, icons, masonry and effects are original
vector drawings rendered through Cairo. The menu, four skies and four soil/rock
materials are original AI-assisted paintings compiled from reviewed PNG masters.
No external service is called when rebuilding. To rebuild everything:

```sh
uv run tools/build_art.py                 # all sections (~90 s on the validation machine)
uv run tools/build_art.py grubs icons     # just some: grubs portraits icons props terrain scenes previews
```

`uv` reads the dependencies (cairocffi, Pillow, numpy) from the script header. numpy
is only used by the preview compositor. Previews invoke the project's Ruby terrain
generator with a fixed seed; no previously generated masks are needed. The build
also needs the system `libcairo.so.2`. It writes the PNGs, the SVG sources and
`assets/art/manifest.json`. Contact sheets and animated GIF previews for review go to
`tools/build_art_previews/`. They are not game assets and should not be packaged.

The [research and asset selection record](ART_RESEARCH.md) explains the reference
study, candidate asset packs, selected audio and visual direction.

## Look & feel

Expressive graphic characters and toy weapons against rich painted environments.
Warm paper, teal and orange unify the menus with the battlefield.

- **Chunky ink outlines** in `#182d35` on every foreground element. Distant scenery uses
  tinted outlines or none, so depth reads clearly.
- **Two-tone cel shading.** Light comes from the upper front. Each shape gets a shade
  crescent, a lit body, and a white gloss capsule.
- **Palette:** ink `#182d35`, warm paper `#f7f2e6`, orange `#f57c49`, teal `#407d80`,
  gold `#edc16d`. Grub skin is peach-pink: `#f9ab98` lit, `#e07f86` shade, `#ffc9a6` belly.
- **Backdrops** use soft atmospheric haze and a light paper grain. Saturation and contrast
  stay lower than the gameplay layer, so terrain and grubs always pop. Anything a player
  could mistake for ground (floating islands, rocks) is pushed onto a hazy distant plane
  with no ink outline.
- **Gameplay layer vs backdrop.** The terrain and characters own the strong values:
  saturated material colours and a dark silhouette rim. Backdrops stay hazier and lighter
  in their lower half, so caves and craters always read as "open air". Per biome, the
  terrain and backdrop are tuned as a pair: meadow loam on teal haze, terracotta
  sandstone on cream and lavender, mid-blue ice on indigo night, charcoal basalt on a
  lava-lit orange glow.
- **No text is baked into any art.** The "×2" on `double_damage` is built from strokes, not
  from a font.

## The grubs

Grubs are soft larvae with an oversized round head and two big googly eyes (a near eye
and a far eye, in 3/4 view). They have brows, a blush, and a segmented belly plate. Every
grub wears a knitted scarf in its team colour with fluttering tails. Each team also has
its own headgear, so teams stay readable even for colour-blind players:

| team | colour    | name    | headgear                         |
|------|-----------|---------|----------------------------------|
| 0    | `#ef765e` | coral   | aviator goggles on the crown     |
| 1    | `#61bdba` | lagoon  | field helmet                     |
| 2    | `#edc56a` | mustard | knotted headband                 |
| 3    | `#ac98cf` | lilac   | pom-pom beanie                   |
| 4    | `#82b67f` | clover  | propeller cap (prop spins)       |
| 5    | `#7faade` | sky     | backwards cap                    |

### Sprite contract

- Files: `grubs/{team}-{state}-{frame}.png`, with a **160×160** transparent canvas (80×80 logical).
- Large browser/results portraits use `grubs/portraits/{team}-{state}-{frame}.png`
  at **512×512**, rendered directly from the same vector pose model. Idle frame 0
  and victory frame 2 are provided for all six teams, keeping enlarged artwork
  sharp without enlarging the gameplay animation cache.
- **Source anchor `(80, 136)`** is the ground contact point. At the recommended
  64×64 logical draw size, place the image at `(x - 32, y - 54.4)`.
  Name/health badges use a minimum readable scale and stay inside actor clipping bounds.
- Sprites **face right**. Pre-mirrored copies with the same anchor are in
  `grubs/left/{team}-{state}-{frame}.png`, so the renderer never has to flip images.
- All frames were checked automatically: nothing touches the canvas edge, and the ink
  outline sits on the anchor line.

| state   | frames | fps | loop | notes |
|---------|--------|-----|------|-------|
| idle    | 4      | 6   | yes  | breathing squash/stretch, eyes wander, scarf sways |
| walk    | 8      | 12  | yes  | inchworm hump travels through the body, head bobs, dust puff on the push-off |
| jump    | 4      | 10  | no   | 0 crouch, 1 launch, 2 tucked apex, 3 falling (choose by vertical velocity) |
| hurt    | 3      | 10  | no   | 0 recoil with impact star, 1 squash, 2 dizzy swirl eyes with orbiting stars |
| victory | 6      | 10  | yes  | hop-dance with happy eyes, confetti and sparkles |
| dead    | 1      | –   | no   | flopped out, X eyes, tongue, halo (non-gory) |
| blink   | 2      | 12  | no   | optional: show briefly every few seconds of idle |

Grounded states (idle, walk, blink, victory and dead) carry a **soft contact shadow**
under the anchor. It is drawn in sprite space, so it stays on the ground while the body
hops in victory, and it shrinks with hop height. Jump and hurt frames carry no shadow
because they can be airborne in play. Every body also gets a volume gradient: warm top
light that falls off into a cooler underside.

The character code (`tools/build_art_grubs.py`) works at any scale. A `Pose` is a spine
spline plus face and expression parameters, so new states (aiming, sliding, using the
jetpack) take a few lines each.

## Weapons & utilities

`weapons/{id}.png`, 128×128 transparent (64×64 logical), with a baked soft drop shadow. All 48 IDs are
present: rocket, mortar, homing, grenade, cluster, sticky, dynamite, mega_bomb, banana,
holy_bomb, shotgun, rifle, minigun, laser, flamethrower, fire_punch, dragon_punch, prod,
bat, axe, airstrike, mine_strike, napalm, meteor, earthquake, sheep, super_sheep, mole,
skunk, cow, mine, turret, barrel, rope, jetpack, parachute, teleport, girder, drill,
blowtorch, heal, shield, freeze, poison, double_damage, low_gravity, wind_control, skip.
They read well at 32 px or larger. SVG sources are in `src/weapons/`.

The ten directional held weapons in `held/` have mirrored copies in `held/left/`.
They point right at zero degrees and use a centred `(64,64)` source anchor.
Three projectile sprites in `projectiles/` separate the actual rocket/shell from
the arsenal illustration. `tools/build_art_combat.py` generates these 128px
rasters; `manifest.json` lists their coverage. The scene rotates held weapons
with aim and projectiles with velocity. Fused projectiles carry a contrast-backed
countdown, with an orange final second.

Some design choices keep these icons clearly original:

- `holy_bomb` is a golden orb with a halo and a four-point star. It has no cross and no
  reference to any film.
- `heal` is a heart with a white plus. It does not use the protected red-cross emblem.
- `sheep` and `cow` are original character designs.

## Backdrops

Each backdrop is **1600×800**. It contains distant scenery, never playable
terrain. The native renderer layers the destructible bitmap and all actors above
it. The lower part stays calm and luminous so a tunnel or crater reads as open air.
The scene draws the painting on an oversized 1536×768 logical plate, with bounded
48×24px parallax margins. Its slow drift adds depth during camera exploration;
the motion preference disables it, and aim/collision coordinates stay independent.

- `sky-meadow.png`: warm sunlight, painted teal alpine ranges, clouds and a quiet lake.
- `sky-desert.png`: peach sunset, distant sandstone buttes and lavender valley haze.
- `sky-glacier.png`: mint aurora, cobalt sky, snow peaks and pale blue frost mist.
- `sky-volcano.png`: a distant mauve volcano, ember-lit cloud and quiet coral haze.

`menu-bg.png` is **1440×900** with an ivory left column and the original grub crew
on an illustrated island on the right. Text is rendered by Scarpe, never baked
into the painting. Check actual text contrast and the small-window composition
when changing this asset or the menu positions.

The source paintings and complete prompts live in
`assets/art/source/paintings/`. `provenance.json` pins each SHA-256 and output size.
`tools/build_art_scenes.py` validates the hashes and aspect ratios, then compiles
RGB PNGs with Lanczos resampling. It fails if a source changes unexpectedly.
Updating a painting means reviewing the master, updating its provenance, and
running `uv run tools/build_art.py scenes`. This is deterministic image asset
compilation, not a fresh generation request. Packaging excludes source masters.

## Terrain material kit

The destructible landscape is a cell bitmap (1 cell = 2 world px, materials 0 air, 1 soil,
2 girder, 3 masonry). `lib/burrow/client/terrain_painter.rb` paints it in the terrain
worker process from the baked textures in `assets/art/terrain/` (built by
`tools/build_art_terrain.py`). The textures are authored **at cell resolution**, so the
painter only does array lookups per cell: no trigonometry, no colour blending.

| file | size (cells) | role |
|---|---|---|
| `{biome}-fill.png` | 512×512 | painted body: earth, boulders and roots (meadow); sandstone and fossils (desert); fractured ice (glacier); basalt and amber veins (volcano) |
| `{biome}-deep.png` | 512×512 | the fill, darkened 12%: more than `DEEP` (24) cells below the air above |
| `{biome}-shade.png` | 512×512 | the fill, darkened 32%: occluded under the surface lip and within 6 cells of air below (cave ceilings, overhangs) |
| `{biome}-edge.png` | 512×512 | the fill, darkened 72%: the 2-cell silhouette rim on undersides and walls |
| `{biome}-crust.png` | 512×20 | the surface lip; row r = r cells below the air above. **Alpha 255** = crust colour, **alpha 0** = fall through to the fill, **any other alpha** = use the shade texture (lip shadow) |
| `{biome}-tufts.png` | 512×12 | optional grass/snow/ash fringe for empty cells above a soil surface. **Off in the shipped painter** (`TUFTS = false`), because the visible mask must equal the collision mask |
| `{biome}-masonry.png` | 128×64 | weathered dressed stone for material 3 |
| `{biome}-masonry-edge.png` | 128×64 | matching stone silhouette shadow |
| `girder.png` | 32×6 | steel girder for material 2; the row is the depth from its top |

Cell rule, in order: girder → masonry (edge rim on its silhouette) → crust if opaque →
edge (≤2 cells above air below, or air left/right) → shade (lip marker, or ≤6 cells
above air below) → deep (more than 24 cells under the air above) → fill. Painted textures repeat by mirrored world-cell coordinates over a 1024-cell
period, so craters cut cleanly through the pattern and worker tiles stitch
seamlessly. The reviewed 512px masters are pinned by hash in
`assets/art/source/materials/provenance.json`. Masonry repeats at 128×64 cells.

Painter invariants:

- **Opaque pixels are exactly the collision mask.** Air cells stay fully transparent.
- **Stitched tiles equal a whole render.** The tile digest covers `RIM_UP = DEEP + 2`
  rows above, `SHADE + 2` rows below and 2 columns either side: everything a tile's
  pixels depend on.
- **Linear cost.** Per column, the painter reads upward only until the first air cell
  (capped at `RIM_UP`). The "air below" pointer only moves forward and stops at the tile
  bottom plus `SHADE + 1`.

`tools/build_art_terrain.py` also contains `paint()`, a numpy reference of the same rule
set used by the previews. The automated terrain tests compare whole and stitched
Ruby renders for every biome and verify exact alpha/collision agreement.

## Props, FX, UI

The table gives **logical** sizes and anchors. All props, FX and HUD rasters are
rendered at **2×** these dimensions, except app icons, which retain their exact
platform sizes. FX metadata retains logical `size`/`anchor` and separately records
`source_size`/`raster_scale`, so higher-resolution pixels never enlarge an effect.

| file | size | notes |
|---|---|---|
| `app-icon.png` (+ `-16/32/48/64/128/512/1024`) | 256 | rounded tile with the hero grub and an explosion |
| `crate.png`, `crate-health.png`, `crate-utility.png` | 64 | weapon, health and utility drops |
| `grave.png`, `grave-{0..5}.png` | 64 | tombstone with a grub-curl engraving; team ribbons; anchor (32,60) |
| `cloud.png`, `cloud-small.png` | 512×128, 128×64 | transparent drifting clouds |
| `mine-prop.png`, `mine-prop-lit.png` | 32 | in-world mine; alternate the two for a blinking light |
| `barrel-prop.png` | 40×48 | in-world explosive drum |
| `fx/explosion-{0..8}.png` | 160 | flash → fireball → smoke ring with debris; anchor centre; 18 fps |
| `fx/smoke-{0..5}`, `fx/dust-{0..4}`, `fx/splash-{0..5}`, `fx/sparkle-{0..3}` | see manifest | small effect loops |
| `ui/crosshair.png`, `ui/wind-arrow.png`, `ui/turn-marker-{0..3}.png` | see manifest | HUD pieces |

`manifest.json` lists every asset with its path, size, frame counts, fps and anchor, plus
a static `terrain` block that describes the kit and its alpha contract.

## Review previews

`tools/build_art_previews/` holds review output only:

- `art-contact-sheet.png`: four combat boards (islands map), a volcano and a glacier
  cavern, and a row of grubs on the terrain fills
- `combat-board-meadow.png`: one full-size 1440×720 board
- `terrain-kit.png`: every texture, with the crust and tufts magnified
- `grubs-*`, `weapons-sheet.png` and `scenes-sheet.png`

The boards follow `scene.rb`'s layers: backdrop, terrain at 2× nearest, props at
their runtime aspect ratios/foot anchors, grubs at 64 px with badges, and water.
The preview build exports `terrain-mask-{islands,cavern}.png` from the real Ruby
generator at seed 314159 and 4800×1600 world pixels. Masks are stored as visible
greys (material id × 80); the resulting boards are review composites, not native
game screenshots. Actual native captures live under `docs/evidence/`.

## Provenance & licensing

- **Foreground artwork is original procedural art.** Character, weapon, masonry, surface,
  prop and FX generators are retained in `tools/build_art_*.py`, with SVG exports
  where applicable. They do not use downloaded or traced game assets.
- **Background and material paintings are AI-assisted.** The built-in imagegen tool generated
  the menu, four skies and four terrain materials during the October 2026 polish pass. Exact prompts and
  output hashes are retained. No Team17 image was supplied; the menu's sole image
  reference was this project's original illustration at revision `e004fce`.
- **Audio includes licensed samples.** The original music and several effects
  remain synthesized by `tools/build_audio.rb`. Twelve selected Kenney CC0 cues
  supplement/replace effects. Canonical mono PCM masters, original download URLs
  and hashes are retained under `assets/audio/source/kenney/`. Full notices ship
  in `assets/audio/KENNEY-NOTICES.txt`. Rebuilding requires no external decoder.
- **Trademark and IP hygiene:** the art contains no names, logos, characters, music or
  assets from Worms / Team17 or any other franchise. Grub design, headgear, palette and
  props were all designed from scratch. Some weapon IDs (for example `banana`,
  `holy_bomb`, `super_sheep`) describe generic gameplay concepts. Their artwork is
  original, but player-facing **display names** should be the game's own (for example
  "Fruit salad", "Choir bomb", "Captain wool").
- **Build-time tools only** (these are not shipped with the art and impose no
  requirements on it):
  - cairo (LGPL-2.1 / MPL-1.1), through cairocffi (BSD-3-Clause)
  - Pillow (MIT-CMU / HPND), used for post-processing: drop shadows, paper grain,
    previews
- The paper grain is uniform noise from a `random.Random` seeded with the CRC-32 of the
  asset name. It is generated at build time, not loaded from a file.

## Reproducible builds

The art build is deterministic. Procedural choices use fixed seeds, painted
backgrounds and materials compile from hash-pinned local masters, and the
manifest carries a fixed `ART_VERSION`. Rebuilding never calls an image service.
Run `uv run tools/check_assets.py` to check coverage, source hashes, canvases,
clipping, opaque materials, audio formats, and notices. Compare SHA-256 manifests
before and after two full art/audio builds to verify byte identity. Current
validation reports record the exact build and environment checked.

## Revision history

- **2026-10-09, presentation polish (`2026.10.09.3`).**
  - Five original painted background masters replace the procedural panoramas and menu.
  - Four painted terrain masters, softer surface crowns and weathered masonry.
  - Retina character, icon, prop and FX rasters; directional held weapons and projectiles.
  - Readable actor/fuse badges, improved camera framing, and unified native screens.
  - Bounded background parallax and brief team-coloured turn cues; camera exploration
    remains manual until Follow, with an explicit prompt when your turn arrives.
  - Rebuilds compile reviewed local sources, with prompts, hashes and dimensions recorded.
  - Licensed Kenney effects add material sound and distinct weapon reports; mono effects
    support camera-relative panning, and music remains stereo.
  - See current validation for the checks actually run; the historical figures below
    describe earlier asset revisions.

- **2026-10-09, round 3.**
  - Terrain: new material kit plus a new `terrain_painter.rb` that replaces the
    procedural brick or patch pattern. It adds a grass, sand, snow or ash lip with a dark
    top line and drips, silhouette rims, occlusion under lips and over cave ceilings, a
    deeper subsoil tone, and textured masonry and girders.
  - Painter speed: the A/B run below was measured before the final forward-scan
    correctness fix, against the 0.2.4 painter, on the same maps. Full renders were at
    parity (islands 2400 wide: 733 vs 736 ms; 4800 wide: 1910 vs 1904 ms; cavern: 1055 vs
    962 ms). Pure tile cost was 2.5× lower (about 7 vs 17 ms per 192² tile); the totals
    are dominated by PNG encoding and the overview. Per-blast rebuilds stayed within
    about ±40 ms, and blasts re-rendered the same number of tiles.
  - Backdrops: all four repainted with the faceted and atmospheric language above; the
    desert and glacier values were retuned against the new terrain.
  - Grubs: contact shadows and body volume. Filenames, frames, anchors and the left
    mirrors are unchanged.
  - Unchanged: icons, props, FX and the menu.

- **2026-10-08, round 2.**
  - Menu: the dark left vignette was replaced by a solid warm ivory panel (x 0–540)
    that fades out by x 720, and the left-side clouds and isle were removed.
  - Backdrops: the twelve outlined foreground islands were replaced by smaller, hazy,
    thin-lined isles on a distant plane, meadow got valley mist, and the windmill and
    icebergs got softer outlines.
  - Build: the grain is now seeded, and the manifest version is pinned.
  - Unchanged: filenames, dimensions, anchors, sprites, icons, props and FX.
