# Presentation research — 9 October 2026

This pass uses Worms W.M.D as a presentation reference for Burrow Brigade, an
independent game. Reference screenshots stay in the ignored working cache;
none are distributed or supplied to image generation.

## What the reference does well

- **Painted environments, graphic actors.** Steam's screenshots show textured,
  irregular landscape masses against atmospheric scenery. Characters, weapons,
  and effects have simpler shapes that remain readable over that detail.
  [Steam screenshots](https://store.steampowered.com/app/327030/Worms_WMD/).
- **Material detail carries the scene.** Team17's retrospective explains why the
  artists retained brush marks and worked at high resolution. It also describes
  composing terrain from painted pieces. That is a useful target for texture
  quality; Burrow Brigade retains its deterministic collision mask and worker
  renderer rather than replacing the map system during a presentation change.
  [Team17's development retrospective](https://www.team17.com/news/team17s-100-games-part-seventeen-2016-overcooked-worms-w-m-d-and-more).
- **Clear visual priority.** The settings, lobby, inventory, targeting and results
  screenshots make the next action easy to identify. Large weapon illustrations,
  compact supporting information and strong selected states are more useful
  than treating every action as an identical form button.
  [Interface In Game's W.M.D collection](https://interfaceingame.com/games/worms-w-m-d/).
- **Controls and framing belong to the design.** A beautiful landscape is only
  useful when the active character, target, shot and impact remain easy to find.
  Manual camera exploration must remain predictable during automated following.
  This is our design conclusion from inspecting gameplay, not a claim about
  Team17's camera implementation.

Additional reading: [David Wood's development interview](https://www.gamewatcher.com/interviews/worms-w-m-d-interview/12653),
[Team17's PlayStation announcement](https://blog.playstation.com/?p=170440), and
[the artist portfolio](https://www.behance.net/gallery/46228585/The-art-of-Worms-WMD).
The portfolio appeared in search but its full page rejected automated retrieval;
the primary retrospective above supplies the verified production account.

## Asset sources assessed

| Source | Fit and license | Decision |
| --- | --- | --- |
| [Kenney Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0; compact click, open, close, warning and tick cues | Selected five cues; source hashes and original notices retained |
| [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) | CC0; tactile impacts with useful short tails | Selected a punch impact |
| [Kenney RPG Audio](https://kenney.nl/assets/rpg-audio) | CC0; physical equipment and movement sounds | Selected latch and throw cues |
| [Kenney Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | CC0; explosive reports, thrust and beams | Selected launch, beam and two explosion weights |
| [Kenney Input Prompts](https://kenney.nl/assets/input-prompts) | CC0; coherent keyboard/mouse glyph set | Downloaded for comparison; use only if it improves the existing UI |
| [GameArt2D freebies](https://www.gameart2d.com/freebies.html) | Freebies are CC0 under the creator's [license](https://www.gameart2d.com/license.html) | Good prototyping tiles; a different visual language from this game's grubs and destruction |
| [CraftPix backgrounds](https://craftpix.net/freebies/free-horizontal-2d-game-backgrounds/) | Commercial game use allowed, with source-redistribution restrictions in the [license](https://craftpix.net/file-licenses/) | Not included in this public source repository |
| [OpenGameArt explosion alternatives](https://opengameart.org/content/2-high-quality-explosions) | Individual attribution/license requirements vary | Compared as an alternative; selected the cohesive Kenney set instead |
| Existing Burrow Brigade foregrounds | Original code-generated characters, 48 icons, FX and deterministic terrain kit | Refine this established set rather than combine incompatible stock styles |

"Best" here means suitable for the actual renderer, readable at gameplay sizes,
cohesive with the rest of the game, and distributable with the source. Download
count or a high-resolution preview alone does not establish that fit.

## Shipped direction

The five new background masters were made with the built-in imagegen tool from
written art direction. Only the menu uses an image reference: the game's own
existing menu illustration, to retain its grub identity and composition.
The exact prompts, master hashes and runtime sizes are recorded in
[`provenance.json`](../assets/art/source/paintings/provenance.json).

The meadow uses sunlit teal mountains; the desert uses sandstone and lavender
haze; the glacier uses aurora and pale frost; the volcano uses mauve basalt
ranges and ember light. All four keep their lower field calm, so caves, craters,
characters and the destructible ground retain visual priority. The menu leaves
an ivory text column and places the illustrated crew on the right.

Four additional original material masters provide the destructible landscape’s
earth, sandstone, ice and basalt. They use written prompts with no reference
images; prompts and hashes live in
[`material provenance`](../assets/art/source/materials/provenance.json).
The compiler bakes shading variants; the worker clips them to the exact host
collision mask. Held weapons and projectiles are generated separately from the
arsenal icons so their direction and silhouette remain clear in combat.

Audio masters are normalized, bounded mono PCM for positional effects, with the
original stereo music retained. Each weapon family gets a suitable report;
healing and passing a turn no longer trigger the common rocket launch cue.
See the [audio provenance](../assets/audio/source/kenney/manifest.json) and
[distribution notices](../THIRD_PARTY.md).

## Acceptance standard

Inspect actual native screenshots of the main menu, settings, rules, arsenal,
lobby, all four biomes, overview and close camera, six-team battle, effects and
results. Check both the smallest supported window and large/2× layouts. Verify
asset rebuilds, sprite anchors and terrain masks, then run native interaction
journeys and frame-pacing checks. Human playtesting and native Mac acceptance
remain separate evidence from Linux screenshots and automated checks.
