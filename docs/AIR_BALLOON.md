# Air Balloon

The Knights' Keep can cast **Launch balloon**. An Air Balloon takes up to 4 crates, flies them to a point the player targets, and sets them down there. The crates come from the balloon's manifest, out of the Keep's stock, or else from beside the Keep.

Round 3 item 7 (2026-11-26, `docs/ROUND3_SKY_PAVILION.md`) added the manifest and lets the balloon fly to any explored land.

The owner asked for it on 2026-11-24. It follows item 7 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), with one change: the balloon is a Keep ability the player casts and targets, not a unit trained at the Keep.

## Using it

1. Select a Keep and press **Launch balloon** (L). The Load page opens as the **balloon manifest**:
   - **Adding crates:** Iron (A), Wood (W), Coal (C) and Food (F) each add a crate of 25 from the Keep's stock, up to 4. Shift fills every free slot.
   - **Taking crates off:** right-click takes one off, and Shift+right-click takes all of that kind. Clear (X) empties the manifest.
   - **The panel:** it shows the crates set, or, with none set, how many crates stand beside the Keep.
   - **Empty manifest:** the balloon takes the full crates packed beside the Keep with **Make crates** (C), as before.
2. Left-click the map or minimap where the crates should go.
   - Shift-click keeps the command armed for another launch. The manifest stays set for the next balloon.
   - Esc or a right-click cancels it.

The Launch balloon tile is greyed out only for a Keep that can't launch at all (destroyed, or a side that isn't playing).

A launch is refused, with the reason told, when:
- **Nothing to carry:** the manifest is empty and no full crate stands beside the Keep.
- **Short of Wood:** the Keep has less than 20 Wood.
- **Short for the manifest:** the Keep's stock can't pay the manifest plus the balloon's Wood. The notice names the kind it lacks.
- **Unexplored point:** on maps with fog of war, the point is on land the side has never explored. It needn't be in sight now.
- **No room:** there is no open land near the point to set crates on.

## What the balloon does

- **Launch:** costs 20 Wood from the Keep.
  - **With a manifest:** the manifest's crates are taken from the Keep's stock.
  - **Without one:** it takes the full crates beside the Keep, at most 4 (100 in all). Any further crates stay beside the Keep.
  - The Keep plays its LaunchBalloon clip, and the balloon lifts off the rooftop dock (6 m up) to its 10 m cruise height.
- **Flight:** straight to the point at 5 m/s, on the air layer, over anything.
  - **No orders:** it can be selected and inspected but takes no orders. If it is stopped, it carries on.
  - **Getting shot down:** it has 40 health, and any unit can shoot it. Shot down, it plays its Die clip and crash effect and drops nothing.
- **Landing:** it comes down at the point and sets the crates on the nearest free land cells, as packed.
  - If it lands inside a friendly Keep's range, it unloads into that Keep instead. Anything the Keep has no room for is set down as crates.
  - Then it is gone. It never returns and never carries units.

Its HUD card shows what it carries.

## Numbers

All are play-test starting points:
- **`assets/economy/knights_rules.tres`, Air Balloon group:**
  - `balloon_wood_cost` 20;
  - `balloon_crates` 4;
  - `balloon_cruise_height` 10 m;
  - `balloon_dock_height` 6 m;
  - `balloon_climb_rate` 2.5 m/s.
- **`assets/units/air_balloon.tres`:**
  - 40 health;
  - 5 m/s;
  - sight 16;
  - the Drone's air mobility.

It takes no housing.

## Files

- **Keep:** `scripts/gameplay/keep.gd` has:
  - the manifest: `balloon_manifest`, `balloon_manifest_add/fill/remove` and `balloon_stock_cost()`;
  - `balloon_crates()`, `balloon_keep_refusal()`, `balloon_refusal(point)` and `launch_balloon(point)`.
- **Balloon:**
  - `scripts/gameplay/air_balloon.gd` extends `unit_agent.gd`. It refuses every order and lands.
  - The unit scene is `scenes/gameplay/air_balloon.tscn`.
- **Model:**
  - `scenes/models/air_balloon_model.tscn` (Rest, Run, Die clips on `character_animator.gd`) and `air_balloon_death_fx.tscn`.
  - Blender source: `Blender/Vehicles/AirBalloon/`.
- **Command card:**
  - **HUD:** the LaunchBalloon tile on the Keep card, slot 2, with key L (`command_launch_balloon`).
    - While it is armed, `skirmish_hud.gd` `balloon_keep()` turns the Load page into the balloon's manifest. `edit_manifest`, `lower_manifest`, `clear_manifest` and `_update_balloon_manifest` handle it.
    - The armed click is handled in `skirmish.gd` `issue_card_order` (`launch_balloon`).
  - **Card art:** the tile borrows the Deliver card art for now.
- **Checks:**
  - `tests/air_balloon_test.gd` (headless) covers:
    - the refusals and the 4-crate cap;
    - the 20 Wood cost and the dock lift-off;
    - refused orders;
    - four crates landing at the point;
    - unloading into a Keep;
    - getting shot down and dropping nothing.
  - `tests/sky_pavilion_roads_troop_train_test.gd` (headless, Two Lakes with fog) covers the manifest:
    - the page and its tiles;
    - the 4-crate cap and taking crates off;
    - unexplored land refused, explored land out of sight taken;
    - the stock paying;
    - the four crates landing;
    - a refusal short of Coal;
    - falling back on crates beside the Keep.
  - `tests/air_balloon_runtime_check.gd` (rendered) shows the lift-off, the flight with its card, the crates once landed, and the manifest page.

## Not done

- **Knights AI:** doesn't launch balloons.
- **Art:** the balloon has no portrait or card art of its own.
- **Point preview:** while it's armed, the map doesn't preview whether the point under the cursor will be refused.
