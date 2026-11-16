# Portal mine model

The Iron Mine that stands in a mine site ([MINE_SITES.md](MINE_SITES.md)) is `assets/models/buildings/portal_mine.glb`, wrapped by `scenes/models/portal_mine_model.tscn` and placed in `scenes/gameplay/site_mine.tscn`. It is a mine dug into the rock: a plated steel portal in a collar of rust-streaked boulders, a track running out of the tunnel with an ore cart on it, a hoist with a bucket over an ore bin, a winch house on a timber trestle and two tanks. It follows the concept picture agreed on 2026-11-15, with the mountain scaled up and the mine scaled down.

It is the same mine as the pithead of [IRON_MINE_MODEL.md](IRON_MINE_MODEL.md) in every rule: `site_mine.tscn` runs the same `iron_mine.gd`, and the model's clips are played by the same `scripts/components/mine_rig.gd`. Only the model differs. `DepotNetwork.site_mine_scene` is the scene built on a mine site; an ore field still gets `mine_scene`, the pithead.

The mine is shared, so it wears no side's colours. The two banners on the portal's piers are plain dark red with a black mark.

## Size

The model fills a mine site's cut: 4 m across and 3 m deep, with the rock collar rising to about 4.5 m against the cut's back wall. Everything solid stays inside the site. Only the track runs on, flat, for 2 m over the strip that a site keeps clear in front. About 11,700 triangles, flat materials only. The front (the tunnel mouth) faces -Y in Blender, which is +Z in Godot; `iron_mine.gd` turns the model to look out of its cut.

## Parts

```
portal_mine_root
  floor          gravel pad, hard standing, the track and its sleepers, a buffer, spilled ore
  rock           the collar of boulders round the portal and up the back wall
  portal         piers, lintel, corner gussets, tunnel lining, banners, railing
  lamps          the lamps over and inside the mouth: hidden once the mine is worked out
  cart           the ore cart on the track
    cart_ore     its load
  hoist          braced post, arm, ladder
    hoist_wheel  the wheel at the end of the arm
    hoist_rope   the rope down to the bucket
    bucket       the bucket
      bucket_ore its load
  ore_bin        the bin under the hoist
    bin_ore      the heap in it
  winch_house    trestle, deck, plated house, stack, railing, ladder
  windows        the house's lit windows and a lamp on the trestle
  smoke_1..3     smoke from the stack
  tanks          two banded tanks and their pipe
```

## Clips

All at 24 frames a second, baked one key a frame, every part keyed in every clip.

- **Idle** (4 s, loops): lamps flicker, the bucket sways a little, a wisp of smoke rises from the stack.
- **Work** (4 s, loops): the cart is emptied, runs into the tunnel and comes out loaded; the bucket goes down into the bin, comes up loaded and is emptied; the smoke thickens. The loop starts and ends as Idle stands, so the rig can switch either way without a jump.
- **Depleted** (4 s, loops): lamps and windows dark, no smoke, the cart, bucket and bin empty, the bucket hanging low.
- **Build** (10 s): the pad, the rock collar, the portal, the winch house, the tanks, the hoist and its wheel, rope and bucket, the bin, the cart, their ore, then the lamps. Nothing stands before the pad appears.
- **Die** (5 s): everything shakes, the lamps go out, the bucket drops, the cart runs out along the track and tips over, the portal pitches forward, the hoist goes over, the winch house and the tanks topple, then the wreck sinks out of sight from 3.6 s.

## Building it

`Blender/Buildings/PortalMine/build/build_portal_mine.py` makes everything in one run: the model, the clips, a review picture (`Blender/Previews/PortalMine/portal_mine_review.png`, from the game's angle), `Blender/Buildings/PortalMine/PortalMine.blend` and the exported GLB. Change the script and run it again rather than editing the file by hand:

```bash
blender --background --python Blender/Buildings/PortalMine/build/build_portal_mine.py
```

Its geometry helpers, animation helpers and materials are the old mine's own: it runs the first section of `Blender/Buildings/IronMine/build/build_mine.py` and of `animate_mine.py`, up to a marker line in each. If those files are reorganised, the two markers named near the top of the script have to follow.

The import settings in `portal_mine.glb.import` matter: constant tracks are kept (`animation/remove_immutable_tracks=false`), because Idle, Depleted and Build hold parts still or hidden with keys that never change, and Idle, Work and Depleted are set to loop.

## Not done yet

- There is no death effect scene (sparks, dust, debris) as the pithead has; `Die` is the model's own motion only.
- The cart's wheels do not turn and the smoke is three plain puffs.
- Site construction shows the plain plan grid round a planned portal mine: the fenced construction-site model only exists for square footprints.
- The model has not been seen in motion in a running game, only as still frames from `tests/mine_sites_runtime_check.gd`.
