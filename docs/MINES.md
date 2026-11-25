# Derailer mines and detection

Item 9 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. Every number is a play-test starting point.

## Derailer price

70 E / 15 I (was 45 / 10), in `assets/units/motorcycle.tres`.

## Minelaying research

The Temple of Science researches **Minelaying** (key N on its card): 150 E / 100 I, 60 s (`assets/research/minelaying.tres`). It works the same way as Mining Trains (`docs/TEMPLE_OF_SCIENCE.md`).

After it, every Derailer of that side can carry 2 mines.

## Loading mines

A Derailer loads mines when all of these hold:
- its side has researched Minelaying;
- it is stopped and idle;
- it is inside a friendly Depot's range or a deployed Cargo truck's range.

**How it loads:** one mine a second, until it carries 2. Each mine takes 10 iron from that Depot or truck. This is the same timing as refuelling. Research alone gives no mines.

**Card:** the Derailer's card shows the **Lay mine** tile (N). When it can't lay a mine, the tile is greyed out with the reason: not researched, or no mines aboard.

## Laying a mine

1. Press **Lay mine** (N), then click a point on the map. The point can be on track. Shift keeps the command armed.
2. The Derailer drives there and works for 2 s.
3. It leaves the mine on the point clicked.

**Arming:** the mine arms 3 s after it is laid. Until then the other side can see it. Once armed, it is hidden (see Detection).

**Setting it off:** an enemy ground unit within 2 m sets it off.
- That unit takes 60 damage.
- The other side's ground units within 3 m take 30.
- Flyers don't set it off.

**On track:** an enemy train that runs onto it derails, as a train on a broken piece does (`docs/DERAILER.md`). The track itself stays.

**Shooting it:** a mine has 20 health. The other side can shoot it while one of its detectors covers it. Units fire at a detected enemy mine in range when no unit or building is in range.

## Detection

A hidden thing is drawn for a side, and can be targeted by it, only while it lies within the detect range of one of that side's detectors. For now the only hidden thing is an armed mine.

Detectors (`scripts/combat/detection.gd`):

| Detector | Range |
| --- | --- |
| Depot, Keep | its own range (`SupplySource.radius`, 26.25 m) |
| Drone | 20 m (`detect_range` in `assets/units/drone.tres`) |
| Warhound | 10 m (`detect_range` in `assets/units/warhound.tres`) |

Nothing else detects. Scouts and Sentinels don't (decided in the handoff).

**Under review:** the owner is asking whether this list favours the Knights.

**Where the check runs:** in the mine itself (`land_mine.gd`), ten times a second. It isn't in the fog-of-war loop the handoff suggested, so mines stay hidden on maps without fog too. On maps with fog, an unarmed mine also shows only where the fog allows.

**Targeting:** an armed mine counts as not seen (`unit_agent.team_sees`) unless one of the side's detectors covers it.

## Files

- **Rules:** `assets/combat/mine_rules.tres` (`MineRules`) holds the carry limit, iron per mine, load, lay and arm times, trigger and splash radii, damage, splash share and health.
- **Mine scene:** `scenes/gameplay/land_mine.tscn`, a placeholder disc with a red fuse and the grenade's blast. It runs `scripts/gameplay/land_mine.gd`.
- **Derailer:** `scenes/gameplay/motorcycle.tscn` carries `mine_rules` and `mine_scene`. The code is in `unit_agent.gd`, next to Derail: `can_carry_mines`, `lay_mine_blocker`, `command_lay_mine`.
- **HUD tiles:**
  - LayMine (Derailer card, slot 9, N);
  - ResearchMines (Temple card, slot 1, N).

  Both borrow the Derail card art for now.
- **Map click:** `skirmish.gd` (`lay_mine`).
- **Check:** `tests/minelaying_test.gd` (headless) covers:
  - the Derailer's price and the research;
  - no loading before Minelaying;
  - loading 2 mines for 20 iron;
  - laying a mine;
  - arming and hiding;
  - detection by a Drone and a Warhound at and beyond their ranges;
  - an undetected mine that can't be targeted;
  - the 60 and 30 damage.

## Not done

- **AI:** the Cyborg AI researches Minelaying and lays mines (`docs/ENEMY_AI.md`, Mines). The Knights have no Derailer.
- **Art:** the mine has no model or card art of its own.
- **Tests:** the train derail on a mine isn't tested.
- **Clicking a mine:** a detected mine can't be clicked for an Attack order. Units fire at it by themselves.
