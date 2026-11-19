# Derailer

Asked for on 2026-11-18: the Motorcycle becomes the **Derailer**, with an ability that derails trains. The numbers are
provisional and wait on playtesting.

## The unit

- The Tank Factory's Motorcycle is now named the Derailer (`display_name` in `assets/units/motorcycle.tres`). Its
  stats, model, rail-spike gun and hotkey (C on the factory card) are unchanged.
- Inside the project it keeps the id `motorcycle`: its files, scenes, card art and the `produce_motorcycle` action.
  Only the name the player sees changed.

## Derail

**Using it:** the Derailer's card has a **Derail** tile (key **E**). Click a piece of rail (anyone's, your own
included) and the Derailer:

1. drives to the middle of the piece;
2. works for 3 seconds;
3. drives a spike into it.

The spike shows on the track, and the Derailer's card shows Derail recharging for 30 seconds. Shift queues it like
other orders.

**What the spike does:** trains do not see it, and routes still run through the piece. The next train onto it
derails:

- **The train:**
  - leaves the track where it is, slewed off the line and rolled onto its side;
  - loses 60% of its full health (a train with less than that is destroyed);
  - keeps any cargo aboard;
  - pauses its supply route;
  - can no longer be sent anywhere.
- **The piece is wrecked and goes.** Its line splits in two; rebuild it from the track either side
  (`docs/RAIL_PLANNING.md`, "Joining track").

**Rules** in `RailRules` (`scripts/rails/rail_rules.gd`, shared by the rail network): `derail_seconds` (3),
`derail_cooldown` (30), `derail_damage` (0.6).

## Not in yet

- Re-railing a derailed train, or clearing the wreck.
- Hiding an enemy's spike from you, or spotting it.
- Derailing from a switch thrown under a train, speed on curves or damaged track (the other hooks in
  `docs/RAIL_PLANNING.md`).

## Code

- **Card:** `Derail` in `skirmish_hud.tscn`, with art `assets/ui/command_cards/sl_derail.png`.
  - It was made from the rail card by `Image` operations: the rail glyph broken, with a spike through the gap. It is
    a placeholder.
  - The `command_derail` action is in `project.godot` and `setup_command_actions.gd`.
- **Order:** `unit_agent.gd`: `command_derail`, `_derail_order`, and `derail_cooldown` for units with the `derail`
  ability. `skirmish.issue_card_order` picks the piece with `RailNetwork.pick_at`.
- **Track:** `track_piece.gd` has `spike()` and `is_spiked()`. Each track scene has a hidden `Visuals/Spike` (the rail
  spike model, its trail hidden), which `spike()` moves to the middle of the piece and shows.
- **Train:** `Train._walk` checks the piece under the train each frame. On a spiked piece it calls `derail()`, which
  calls `RailNetwork.wreck()` for the piece.

## Checks

`tests/derailer_test.gd` (headless):

- the Derailer's name and its Derail card;
- arming Derail and clicking a piece;
- the spike placed in time, then recharging;
- a train derailing on it: stops, tips, loses its share of health;
- the piece removed and the line split;
- the train staying put.

Rendered screenshots of the spike on the track and the derailed train beside the gap were looked at.
