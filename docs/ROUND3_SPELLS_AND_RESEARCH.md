# Round 3: Stimulus, Sundering Lances and Forest Camouflage

Item 3 of the Round 3 balance handoff (2026-11-25). Stacked on item 2 (`docs/ROUND3_UNIT_STATS.md`), which adds the Dragon's `giant` flag.

## Mist and Slow from 24 m

`SpellRules.cast_range` is now 24 m (it was 20). The Sentinel walks within 24 m of the point and casts.

Slow now says plainly what it already did: it slows vehicles too (a Tank, a truck), since they move the way units do. It doesn't slow trains, which run on their track; trains are now skipped by name (`rail_trains`).

## Vitality Stimulus (E)

A third spell on the Grail Sentinel's card, after Mist (Q) and Slow (W).

| | |
| --- | --- |
| Cost | 35 reserve points (`stimulus_cost`) |
| Cast range | 14 m (`stimulus_cast_range`) |
| Radius | 5 m (`stimulus_radius`) |
| Effect | +25% move speed and attack rate (`stimulus_boost`) |
| Lasts | 7 s (`stimulus_seconds`) |

- **Who gets it:** your own units in the circle that aren't vehicles (`unit_agent.takes_stimulus`). The Azure Dragon counts; Tanks, trucks and trains don't.
- **No stacking:** a second Stimulus restarts the 7 s; it doesn't add another 25%.
- **How it works:**
  - `speed_scale()` multiplies by the boost, so a slowed and stimulated unit moves at 0.6 × 1.25;
  - the reload after a shot is divided by it (`attack_rate_scale()`).
- **Needs no research.**
- **Its look:** `scenes/gameplay/stimulus_field.tscn`, the Slow sigil recoloured green and gold. It turns the other way and pulses faster, for the 7 s. The Sentinel's cast uses the gold Mist burst.

**Naming:** the Sentinel's healing was labelled "Vitality Stimulus" on the HUD. It is now just "Heal", so the name belongs to the new spell.

## Forge research

The Forge card now has a fifth tile (`Upgrade5`, key T). Its research tiles are Arms (Q), Mail (W), Slow (E), Sundering Lances (R) and Forest Camouflage (T).

Research can now cost coal (`ResearchStats.coal_cost`):
- the Forge pays it from the Keep (`payer_for` takes coal);
- Cancel gives it back;
- the cost reads "125 F · 150 I · 100 C".

| Research | Cost | Time |
| --- | --- | --- |
| Sundering Lances (`Research.SUNDERING`, `assets/research/sundering_lances.tres`) | 125 F / 150 I / 100 C | 60 s |
| Forest Camouflage (`Research.CAMOUFLAGE`, `assets/research/forest_camouflage.tres`) | 75 F / 100 I / 50 C | 45 s |

The effects' numbers are in `assets/combat/forge_research_rules.tres` (`ForgeResearchRules`).

### Sundering Lances

The Questing Marine carries the `sundering_lances` ability. Once its side has the research:
- **Marking:** its hit on an armoured unit (a Tank, Ubermech, truck or train) or a giant one (the Dragon) marks it sundered for 4 s (`sunder_seconds`). A light unit isn't marked.
- **Effect:** every hit on a sundered unit, from anyone, deals 3 more after armour (`sunder_bonus`). Armour is applied first (`maxi(1, hit − armour level)`), then the 3 is added. So a 1 against Mail I still does 4.
- **Timing:** the marking hit itself does its normal damage; the bonus starts with the next hit. A new mark restarts the 4 s.

The marking happens in `CombatResolver.sunder`, called after each hit in `strike` and `strike_at`. The bonus is in `unit_agent.take_damage`.

### Forest Camouflage

The Warhound carries the `forest_camouflage` ability. Once its side has the research:
- **Hidden in forest:** a Warhound standing on a forest cell is hidden from the other side. The only exception is a detector covering it: a Depot or Keep at its range, a Drone within 20 m, or a Warhound within 15 m.
- **Grace:** after it leaves the forest it stays hidden for 1.5 s (`camo_leave_grace`).
- **Attacking:** a bite shows it for 2 s (`camo_attack_break`).
- **Hidden means:**
  - the other side's units can't pick it or shoot it (`team_sees`);
  - on a map with fog, the viewer doesn't see it drawn (`fog_of_war.gd`).

**Detection, generalized:** `scripts/combat/detection.gd` now has `is_camouflaged(node)` (an armed mine, or a unit whose `camouflaged()` is true) and `hidden_from(node, side)`. Mines, `team_sees` and the fog all ask `hidden_from`.

## AI

The Knights AI researches Sundering Lances right after Slow, once home holds its coal. Until then it leaves it out, so the wait for coal holds up no other research. It does not cast Stimulus yet.

## Cards

`render_hud_images.gd` renders three new cards from the units' own models:
- `sl_stimulus.png`: the Sentinel;
- `sl_research_sundering_lances.png`: the Questing Marine;
- `sl_research_forest_camouflage.png`: the Warhound.

They stand in until drawn cards replace them, as Mist and Slow's were.

## Checks

`tests/sunder_stimulus_camo_test.gd` (headless, in the suite) checks four things.

**Spells:**
- Slow is cast from 22 m without walking and slows an enemy Tank to 60%;
- Stimulus costs 35;
- a Marine, a Warhound and the Dragon in range move and attack 25% faster; a friendly Tank and an enemy don't;
- a stimulated Marine reloads in interval / 1.25, and a stimulated Warhound runs faster;
- a second Sentinel walks within 14 m, and its cast restarts the time without adding up;
- Stimulus wears off after 7 s.

**Forge:**
- the two research prices and times, and the cost text;
- Sundering Lances waits without coal, takes 100 coal, and Cancel gives it back.

**Sundering:**
- no mark before the research, and none from a Round Table Marine;
- the marking hit is unchanged; then 10 → 13, with Vehicle Armour I 10 → 12, and 1 → 4;
- the Dragon is marked and Infantry isn't;
- after 4 s the bonus is gone.

**Camouflage, on Two Lakes:**
- before the research the Warhound is seen;
- after it, the Warhound in forest is hidden from a Deforester 2 m away, in both targeting and drawing, and a Drone detects it;
- out of the forest it shows after 1.5 s;
- a bite shows it for 2 s.

`upgrades_test` now expects the Forge's 9 research entries, its five tiles, the new cards and the coal on the tile.

## Not done

- **Art:** no mark on a stimulated, sundered or camouflaged unit. The Stimulus sigil on the ground is the only sign.
- **Camouflage without fog:** on a map with no fog (First Contact) a camouflaged Warhound is still drawn, but it can't be targeted.
- **AI casts:** the AI doesn't cast Stimulus.

Not checked by a person: the feel of all three in play.
