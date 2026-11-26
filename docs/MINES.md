# Derailer mines and detection

Item 9 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. Every number is a play-test starting point.

## Derailer price

70 E / 15 I (was 45 / 10), in `assets/units/motorcycle.tres`.

## Minelaying research

The Temple of Science researches **Minelaying** (key N on its card): 150 E / 100 I, 60 s (`assets/research/minelaying.tres`). It works the same way as Mining Trains (`docs/TEMPLE_OF_SCIENCE.md`).

After it, every Derailer of that side can carry 2 mines.

## Buying mines

Asked for on 2026-11-25: a mine is bought by clicking, not loaded by itself. Each press of **Buy mine** (Q) on the Derailer's card buys one mine, when all of these hold:
- its side has researched Minelaying;
- it carries fewer than 2;
- it is inside a friendly Depot's range or a deployed Cargo truck's range, and that stockpile has 10 iron.

The 10 iron is taken from that Depot or truck at once. With several Derailers selected, each buys one. Research alone gives no mines, and a Derailer never buys one by itself.

**Card:** the Derailer's card shows **Buy mine** (Q), **Lay mine** (E) and **Derail** (R). When Buy mine or Lay mine can't be used, its tile is greyed out with the reason: not researched, full, out of range, or no mines aboard.

## Laying a mine

1. Press **Lay mine** (E), then click a point on the map. The point can be on track. Shift keeps the command armed.
2. The Derailer drives 1.75 m past the point along its way (`LAY_STANDOFF`), so the point is just behind it, and stops. If it can't reach that stand in three tries it drives up to the point instead. It works for 2 s once stopped there, or within 2.5 m of the point.
3. It leaves the mine on the point clicked. The rider lifts the mine from its tray and lowers it there (docs/MOTORCYCLE_MODEL.md).

**Arming:** the mine arms 3 s after it is laid. Until then the other side can see it. Once armed, it is hidden (see Detection).

**Setting it off:** an enemy ground unit within 2 m sets it off.
- That unit takes 60 damage.
- The other side's ground units within 3 m take 30.
- Flyers don't set it off.

**On track:** an enemy train that runs onto it derails, as a train on a broken piece does (`docs/DERAILER.md`). The track itself stays.

**Shooting it:** a mine has 20 health. The other side can shoot it while one of its detectors covers it. Units fire at a detected enemy mine in range when no unit or building is in range.

## Detection

A hidden thing is drawn for a side, and can be targeted by it, only while it lies within the detect range of one of that side's detectors. The hidden things are an armed mine and, since Round 3, a camouflaged Warhound (`Detection.is_camouflaged`, `hidden_from`; `docs/ROUND3_SPELLS_AND_RESEARCH.md`).

Detectors (`scripts/combat/detection.gd`):

| Detector | Range |
| --- | --- |
| Depot, Keep | its own range (`SupplySource.radius`, 26.25 m) |
| Drone | 20 m (`detect_range` in `assets/units/drone.tres`) |
| Warhound | 15 m (`detect_range` in `assets/units/warhound.tres`; 10 until Round 3) |

Nothing else detects. Scouts and Sentinels don't (decided in the handoff).

**Under review:** the owner is asking whether this list favours the Knights.

**Where the check runs:** in the mine itself (`land_mine.gd`), ten times a second. It isn't in the fog-of-war loop the handoff suggested, so mines stay hidden on maps without fog too. On maps with fog, an unarmed mine also shows only where the fog allows.

**Targeting:** an armed mine counts as not seen (`unit_agent.team_sees`) unless one of the side's detectors covers it.

## Selecting and attacking a mine

- **Selecting:** click a mine you can see (your own, or the other side's while detected) to select it. Its card shows its side, whether it is armed, its health and what it does. It has no commands. The card shows the mine's own icon and portrait (`assets/ui/renders/land_mine.png`, `assets/ui/portraits/land_mine.png`), and its meshes are what the click picks (`selection_bounds.gd`): the 0.91 m disc and its prongs.
- **Attacking:** right-click a detected enemy mine with units selected, or use Attack (A) and click it. The units shoot it until it is destroyed. An undetected mine can't be clicked; an attack ordered while it was detected waits for it to be detected again before firing.
- Units still fire at a detected enemy mine in range by themselves, as before.

## Files

- **Rules:** `assets/combat/mine_rules.tres` (`MineRules`) holds the carry limit, iron per mine, lay and arm times, trigger and splash radii, damage, splash share and health.
- **Mine scene:** `scenes/gameplay/land_mine.tscn` runs `scripts/gameplay/land_mine.gd`. Its model (`scenes/models/land_mine_model.tscn`) and blast (`scenes/models/land_mine_blast.tscn`) are in docs/LAND_MINE_MODEL.md.
- **Derailer:** `scenes/gameplay/motorcycle.tscn` carries `mine_rules` and `mine_scene`. The code is in `unit_agent.gd`, next to Derail: `can_carry_mines`, `buy_mine_blocker`, `command_buy_mine`, `lay_mine_blocker`, `command_lay_mine`. Picking a mine is in `selection_manager.gd` (`pick_object`) and `skirmish.gd` (`pick_enemy_mine`); its card is `skirmish_hud.gd` `show_land_mine`.
- **HUD tiles:**
  - BuyMine (Derailer card, slot 10, Q);
  - LayMine (Derailer card, slot 9, E);
  - ResearchMines (Temple card, slot 1, N).

  Their cards are `sl_buy_mine.png` (a mine dropping into the Derailer's tray), `sl_lay_mine.png` (a mine arming) and `sl_research_minelaying.png` (the Derailer with a mine in each tray), rendered by `scripts/tools/render_hud_images.gd`.
- **Map click:** `skirmish.gd` (`lay_mine`).
- **Check:** `tests/minelaying_test.gd` (headless) covers:
  - the Derailer's price and the research;
  - the Q, E and R keys;
  - no buying before Minelaying, and no loading by itself after;
  - buying 2 mines for 20 iron, one a click, and no third;
  - laying a mine;
  - arming and hiding;
  - detection by a Drone and a Warhound at and beyond their ranges;
  - an undetected mine that can't be targeted;
  - the 60 and 30 damage;
  - selecting a mine, and an ordered attack that fires only once it is detected and destroys it.

## Not done

- **AI:** the Cyborg AI researches Minelaying and lays mines (`docs/ENEMY_AI.md`, Mines). The Knights have no Derailer.
- **Tests:** the train derail on a mine isn't tested.
