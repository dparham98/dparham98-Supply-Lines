# Round 3: the Sky-Pavilion and the Supply Balloon's manifest

Part of item 7 of the Round 3 balance handoff (2026-11-25), for the Knights. Stacked on item 6 (`docs/ROUND3_HEARTH_WAIN.md`). The rest of item 7, troop cars, Railheads and Food on trains, is in `docs/ROUND3_TROOP_TRAINS.md`.

- **Sky-Pavilion:** a Keep's **Found Keep (P)** charters one. It flies to land the side has explored and unfolds into a new Keep with a Forester Maiden.
- **Supply Balloon:** the Keep's **Launch balloon (L)** now takes a manifest of up to 4 crates straight from the Keep's stock. It can fly to any land the side has explored.

**King's Roads** (Build → Road) are not built. The handoff said to ask the owner first, since they skipped roads before.

## Sky-Pavilion

**Ordering it.** Select a Keep, press **Found Keep (P)**, then left-click the site.
- **The click:** it must be a site where a Keep could stand, on land the side has explored. It needn't be in sight now.
- **The order:** it then joins the Keep's queue, paying 50 Wood, 50 Iron and 45 Food from that Keep and taking 1 housing.
- **Prep:** after 15 s of prep the pavilion lifts off. Cancel production refunds it and forgets the site.
- **Shift-click:** queues another pavilion to another site.
- **Refusals** (`Keep.pavilion_refusal`), each told with a notice:
  - **Unexplored:** a corner of the 10 x 10 footprint is on land never explored: "Send the Sky-Pavilion to land you have explored."
  - **Bad land:** the footprint isn't open land clear of plans (`DepotNetwork.keep_site_refusal`).
  - **Too close:** it breaks the Depot spacing, 52.5 m from the side's other Keeps and Depots on Two Lakes.
  - **No housing:** the side has no housing to spare.
  - **Short of stock:** the Keep lacks the price.

**The flight.** It lifts off the Keep's rooftop dock (6 m) to `pavilion_cruise_height` (11 m) and flies straight to the site at 5.5 m/s on the air layer.
- **No orders:** like the balloon it takes no orders, and if stopped it carries on.
- **Shot down:** it has 80 health and any unit can shoot it. Shot down, it drops nothing and its housing is freed.

**The landing.**
- **Site still good:** it unfolds into an empty Keep of the side (no Food, Wood or Iron) and a Forester Maiden at the new Keep's gate (`DepotNetwork.found_keep`). Its housing passes to the Maiden, and the new Keep adds its own housing room.
- **Site taken:** if something has taken the site in the meantime, it sets down 2 Wood and 2 Iron crates (50 each) and the Maiden instead.

**The HUD.**
- **Tile:** the Keep card's FoundKeep tile (slot 3, P, `command_found_keep`). It shows the price with what's short, and its tip explains the rest.
- **While flying:** the pavilion's card is titled SKY-PAVILION and says it is flying to found a Keep.
- **Art:** its icon, portrait and card are rendered from the Air Balloon's model scaled 1.4x (`render_hud_images.gd -- sky_pavilion`), until it has art of its own.

## Supply Balloon manifest

`docs/AIR_BALLOON.md` describes the balloon in full. What changed:
- **The manifest page:** Launch balloon (L) opens the Load page as the balloon's manifest.
  - **Choosing crates:** Iron (A), Wood (W), Coal (C) and Food (F) each add a crate of 25 from the Keep's stock, up to `balloon_crates` (4). Shift fills, right-click takes one off, and Clear (X) empties it.
  - **No Energy:** the page has no Energy tile.
  - **The panel:** it reads "Balloon manifest · N / 4 crates".
- **Launching:** the launch takes the manifest's crates and the balloon's 20 Wood from the Keep's stock. A Keep short of either refuses, naming what it lacks. The manifest stays set for the next balloon.
- **Empty manifest:** the balloon takes the full crates packed beside the Keep, as before.
- **The target:** any land the side has explored, in sight or not, with open land near it for the crates (it was: in sight now).
- **The tile:** it greys out only for a Keep that can't launch at all, so the page opens even with nothing set.

## Numbers

| What | Where | Value |
| --- | --- | --- |
| Sky-Pavilion price | `assets/units/sky_pavilion.tres` | 50 W / 50 I / 45 F |
| Prep | `assets/units/sky_pavilion.tres` | 15 s |
| Health, speed, sight | `assets/units/sky_pavilion.tres` | 80 / 5.5 m/s / 20 m |
| Mobility | `assets/units/sky_pavilion.tres` | the Drone's air layer |
| Housing | `assets/economy/knights_rules.tres` | 1 |
| Cruise height | `assets/economy/knights_rules.tres` | 11 m |
| Blocked-site crates | `scripts/gameplay/sky_pavilion.gd` | 2 Wood + 2 Iron of 25 |
| Balloon crates | `assets/economy/knights_rules.tres` | 4 of 25 |

## Files

- **Sky-Pavilion:**
  - `scripts/gameplay/sky_pavilion.gd` extends `air_balloon.gd`. `air_balloon.gd` now asks `cruise_height()`.
  - The unit scene is `scenes/gameplay/sky_pavilion.tscn`.
- **Keep:** `scripts/gameplay/keep.gd` has `pavilion_scene`, `pavilion_sites`, `pavilion_refusal(point)`, `request_pavilion(point)` and `_launch_pavilion()`, plus the balloon manifest (see `docs/AIR_BALLOON.md`).
- **Founding:** `scripts/economy/depot_network.gd` has `keep_site_refusal(point, team)` and `found_keep(point, team)`.
- **HUD:**
  - `skirmish_hud.gd`: the FoundKeep tile, the pavilion's card and the balloon manifest page (`balloon_keep()`, `_update_balloon_manifest`).
  - `skirmish.gd`: the armed `found_keep` click.

## Checks

`tests/sky_pavilion_roads_troop_train_test.gd` (headless, in the suite). The pavilion and balloon sections play on Two Lakes with the Knights at home and fog of war on.
- **Sky-Pavilion:**
  - its price, prep, health and housing;
  - unexplored land refused;
  - the tile arms the click;
  - a scout explores the site and leaves, and the site is taken while out of sight;
  - the Keep pays, and Cancel refunds;
  - it lifts off after 15 s from the dock, and takes no orders;
  - it lands and unfolds into an empty Keep with a Maiden, its housing passing to her;
  - a second one finds its site taken by a Keep and sets down 2 Wood and 2 Iron crates and a Maiden.
- **Balloon manifest:**
  - the page and its tiles, the 4-crate cap and taking crates off;
  - unexplored land refused;
  - the stock paying 4 crates and the Wood;
  - the crates landing;
  - short of Coal refused;
  - falling back on crates beside the Keep.
- **Rendered:** `tests/air_balloon_runtime_check.gd` adds a shot of the manifest page.
- **Elsewhere:** `tests/command_cards_test.gd` counts 86 tiles.

## Not done

- **King's Roads:** not built. They wait for the owner's go-ahead (above).
- **Site preview:** the handoff's green/red Keep-site preview with the spacing ring isn't drawn while Found Keep is armed. A refused click says why.
- **AI:** the Knights AI neither charters pavilions nor sets balloon manifests.
- **Art:** the pavilion uses the balloon's model, scaled, with no banners.
- **Not played:** nobody has played any of this yet.
