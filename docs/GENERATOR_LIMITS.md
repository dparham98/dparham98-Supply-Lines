# Generator cost, coal output, energy ceiling and coal reserve

Step 7 of `docs/ECONOMY_REPORT.md`, accepted by the user. Values are provisional until played.

## Cost and output

- **Cost:** a Generator costs 0 E / 40 I (was 100 E / 20 I), in `assets/economy/supply_rules.tres`. The first one no longer needs energy you can only get from a Generator.
- **Coal:** 1 coal makes 30 E over 3 s (was 50 E over 5 s), in `assets/economy/generator_rules.tres`. The rate is still 10 E/s. Wood is unchanged at 10 E over 2 s.

## Depot limits

Each Depot has two settings that its assigned Generators follow (`scripts/gameplay/depot.gd`):

- **Energy ceiling** (`energy_ceiling`, default 600): a Generator starts a cycle only while its Depot holds less energy than this, and burns no fuel while it waits. A cycle once started finishes, so the Depot reaches the ceiling and may pass it by less than one cycle (up to 29 E with coal), rather than stopping short of it. It still also needs free storage, as before.
- **Coal kept for vehicles** (`coal_reserve`, default 60): a Generator never burns its Depot's coal below this, so vehicles can refuel. Wood has no reserve. In Either mode it burns all the wood, then only the coal above the reserve.

The player sets both on the Depot card, with two buttons that step through presets each press:

| Button | Slot | Key | Presets |
|---|---|---|---|
| Energy ceiling | 4 | H | 300, 600, 1000, then the Depot's own storage capacity, which is no ceiling (shown as "none (full storage)"). Steps at or above the capacity are left out. |
| Coal kept | 5 | J | 0, 30, 60, 120 |

- **Art:** the ceiling uses the Generator pause card and the reserve the auto-refuel card, so neither looks like Make Crates.
- The Depot card's stats show both values, for your own Depots only. A press also posts a notice.
- **Generator card:**
  - The state line says "Paused · Depot at its 600 E ceiling" or "Waiting · 60 coal kept for vehicles".
  - Fuel left counts only what the Generator may burn.
- **Not changed:**
  - Refuelling vehicles still draws any of the Depot's coal, the reserve included.
  - Production and construction spend energy above the ceiling as before.

- **`generator_exercise.tscn`:** its 10 authored coal is below the 60 kept, so its Generator burns only wood there unless the reserve is lowered.

## Checks

- **`tests/generator_limits_test.gd`** (new, headless) checks:
  - the cost and coal values
  - the 600 E / 60 coal defaults
  - a Generator stops short of the ceiling without burning coal, and runs on when the ceiling is raised
  - coal is burnt down to the reserve and no further, with the matching state lines
  - Either mode keeps the reserved coal
  - lowering the reserve frees coal
  - a latched wood cycle whose wood is taken waits for wood, not for the reserve
  - the presets wrap round, and end at the Depot's own storage capacity
  - the Depot card shows both buttons with their keys (H and J when added; E and Q since PR #75), and the stats; a press steps the setting; another side's Depot shows none of them
  - a Generator plan is built for 40 iron and no energy
- **`tests/generator_batch_test.gd`** now runs its cycle checks with fixed rules (coal 50 E over 5 s, no reserve, ceiling at capacity), so it keeps testing the cycle mechanics alone.
- **`tests/command_cards_test.gd`:** counts the two new tiles, and fuel left counts coal above the reserve.
- **`tests/hud_hotkeys_test.gd`:** the Depot card's keys now include H and J (E and Q since PR #75).
- **Older payment checks:** six of them use a Generator only as a priced build, and they keep its old 100 E / 20 I price at their start:
  - `bottom_hud_test`
  - `supply_test`
  - `site_construction_test`
  - `pending_construction_test`
  - `mobile_supply_test`
  - `hud_click_test`
- **`generator_model_test`:** lifts the ceiling, since it checks the model.
