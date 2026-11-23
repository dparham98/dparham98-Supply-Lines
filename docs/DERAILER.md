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
3. breaks it.

Derail then recharges for 30 seconds, shown on the card. Shift queues it like other orders.

Until 2026-11-22 the Derailer drove in a spike that stayed in the track, and the next train onto it derailed. Since the
playtest of that day it destroys the piece outright.

**What breaking a piece does:**

- **The piece goes.** Its line splits in two. Trains whose route ran through it stop, and supply routes wait for the
  rail as they do when track is removed any other way.
- **A train standing on it derails:**
  - it leaves the track where it is, slewed off the line and rolled onto its side;
  - it loses 60% of its full health (a train with less than that is destroyed);
  - it keeps any cargo aboard;
  - its supply route pauses;
  - it can no longer be sent anywhere.
- **A wreck is left:** the piece's model, sunk, canted and scorched, with the spike standing in its middle. It is not
  track: trains cannot use it and it marks no ground. It belongs to the side whose line the piece was on.
- **Messages:** your own track broken (by anyone) tells you how to rebuild it: "Rebuild: Rail (R), click the wreck". Breaking enemy track says "Enemy track destroyed".

## Rebuilding

**What to do is shown** to the wreck's owner only (2026-11-22 playtest: the owner needed a visual indicator):

- **Over the wreck:** a pulsing marker, the Rail tile's icon above amber "TRACK DESTROYED / Rail (R), click here to
  rebuild · N iron" (`RebuildMarker` in `track_wreck.tscn`, with its `Pulse` animation).
- **Alert feed:** a "Track destroyed" alert at the wreck; clicking it moves the camera there.
- **Minimap:** an amber cross, pulsing, on each of your wrecks until it is rebuilt (`tactical_minimap.gd`).

Arm the Rail tile (R) and move the cursor over a wreck of your track. The cursor label shows "WRECKED TRACK", the
piece's iron, and "CLICK REBUILDS IT" or "NOT ENOUGH IRON". A click lays the same piece again, in the same place, and
leaves track laying, as laying any track does.

- **Who pays:** the pinned payer, if Pin is set; else the Depot that paid for the piece, if it is still yours and has
  the iron; else your nearest Depot with it. It costs what the piece costs new.
- **Blocked:** if something now stands where the piece was, the game says so.
- **Wrecks only matter for rebuilding.** Track laid over a wreck any other way, for example a suggested route through
  the gap, clears it as well.
- A click on a wreck comes before picking track, so it works with or without a building already picked. It does not
  take the place of laying a suggested track: once a track is suggested, a click lays that.

**Rules** in `RailRules` (`scripts/rails/rail_rules.gd`, shared by the rail network): `derail_seconds` (3),
`derail_cooldown` (30), `derail_damage` (0.6).

## Not in yet

- Re-railing a derailed train, or clearing it.
- Rebuilding by the enemy's side: the enemy has no track-laying AI yet.
- Derailing from a switch thrown under a train, speed on curves or damaged track (the other hooks in
  `docs/RAIL_PLANNING.md`).

## Code

- **Card:** `Derail` in `skirmish_hud.tscn`, with art `assets/ui/command_cards/sl_derail.png`.
  - It was made from the rail card by `Image` operations: the rail glyph broken, with a spike through the gap. It is
    a placeholder.
  - The `command_derail` action is in `project.godot` and `setup_command_actions.gd`.
- **Order:** `unit_agent.gd`: `command_derail`, `_derail_order`, and `derail_cooldown` for units with the `derail`
  ability. `skirmish.issue_card_order` picks the nearest piece of any side's track under the click.
- **Breaking:** `RailNetwork.destroy` derails trains on the piece (`Train.derail`), leaves the wreck, and removes the
  piece. `piece_team` says whose it was.
- **Wreck:** `scenes/gameplay/track_wreck.tscn` with `scripts/rails/track_wreck.gd`. The scene holds all four track
  models with the wreck material and the spike; the wreck shows the model of its kind and stands the spike in the
  piece's middle.
- **Rebuilding:** `wreck_at`, `wreck_payer` and `rebuild` in `rail_network.gd`; `route_status` shows the label; the
  Rail tile's click in `skirmish.gd` calls `rebuild`. `register` clears wrecks under any new piece.

## Checks

`tests/derailer_test.gd` (headless):

- the Derailer's name and its Derail card;
- arming Derail and clicking a piece;
- the piece broken in the set time, then recharging;
- the piece removed and the line split;
- a train standing on it derailing: stops, tips, loses its share of health, and stays put;
- the wreck left, the player's, showing the right model;
- the rebuild marker over it (and none on another side's wreck) and the alert;
- the Rail tile's label over the wreck, and a click rebuilding the same piece for its iron, joining the line and
  clearing the wreck.
