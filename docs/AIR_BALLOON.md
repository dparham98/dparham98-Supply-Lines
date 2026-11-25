# Air Balloon

The Knights' Keep can cast **Launch balloon**. An Air Balloon takes crates packed beside the Keep, flies them to a point the player targets, and sets them down there.

The owner asked for it on 2026-11-24. It follows item 7 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), with one change: the balloon is a Keep ability the player casts and targets, not a unit trained at the Keep.

## Using it

1. Select a Keep and pack crates beside it with **Make crates** (C). The crates can be Food, Wood or Iron, in any mix.
2. Press **Launch balloon** (L), then left-click the map where the crates should go.
   - Shift-click keeps the command armed for another launch.
   - Esc or a right-click cancels it.

The Launch balloon tile is greyed out, with the reason in its tip, when:
- no full crate stands beside the Keep;
- the Keep has less than 20 Wood.

A click is refused when:
- the point isn't one the player can see now (on maps with fog of war);
- there is no open land near the point to set crates on.

## What the balloon does

- **Launch:** costs 20 Wood from the Keep. It takes the full crates beside the Keep, at most 4 (100 in all). Any further crates stay beside the Keep.
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

- **Keep:** `scripts/gameplay/keep.gd` has `balloon_crates()`, `balloon_refusal(point)` and `launch_balloon(point)`.
- **Balloon:**
  - `scripts/gameplay/air_balloon.gd` extends `unit_agent.gd`. It refuses every order and lands.
  - The unit scene is `scenes/gameplay/air_balloon.tscn`.
- **Model:**
  - `scenes/models/air_balloon_model.tscn` (Rest, Run, Die clips on `character_animator.gd`) and `air_balloon_death_fx.tscn`.
  - Blender source: `Blender/Vehicles/AirBalloon/`.
- **Command card:**
  - **HUD:** the LaunchBalloon tile on the Keep card, slot 2, with key L (`command_launch_balloon`). The armed click is handled in `skirmish.gd` `issue_card_order` (`launch_balloon`).
  - **Card art:** the tile borrows the Deliver card art for now.
- **Checks:**
  - `tests/air_balloon_test.gd` (headless) covers:
    - the refusals and the 4-crate cap;
    - the 20 Wood cost and the dock lift-off;
    - refused orders;
    - four crates landing at the point;
    - unloading into a Keep;
    - getting shot down and dropping nothing.
  - `tests/air_balloon_runtime_check.gd` (rendered) shows the lift-off, the flight with its card, and the crates once landed.

## Not done

- **Knights AI:** doesn't launch balloons.
- **Art:** the balloon has no portrait or card art of its own.
- **Tests:** the fog refusal isn't tested, because the Arthurian test map has no fog.
