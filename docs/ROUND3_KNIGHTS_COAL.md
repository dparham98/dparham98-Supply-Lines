# Round 3: Knights coal, the Stoke Brazier and lakeside Farms

Item 5 of the Round 3 balance handoff (2026-11-25). Stacked on item 4 (`docs/ROUND3_CYBORG_ECONOMY.md`).

Coal becomes the Knights' third resource for war. The Forge's research and the Dragon cost Coal from the Keep. A new toggle, the **Stoke Brazier**, burns Coal to make a Chapterhouse, Dragon Yard or Forge work 1.6x faster. A Farm by a lake grows more Food.

## Coal prices

Paid from the Keep (or the stockpile in range that can pay), and given back on Cancel:

| What | Food | Iron | Coal | Time |
| --- | --- | --- | --- | --- |
| Arms I / Mail I | 100 | 150 | 75 | 60 s |
| Arms II / Mail II | 150 | 250 | 150 | 90 s |
| Arms III / Mail III | 200 | 350 | 225 | 120 s |
| Slow | 100 | 125 (was 100) | 75 | 60 s |
| Sundering Lances | 125 | 150 | 100 | 60 s |
| Forest Camouflage | 75 | 100 | 50 | 45 s |
| Azure Dragon (Dragon Yard) | 160 | 60 | 25 | 40 s, 4 housing |

- **Where the numbers live:** research is on `assets/research/**/*.tres` (`ResearchStats.coal_cost`, from item 3), and the Dragon on `assets/units/azure_dragon.tres` (`UnitStats.coal_cost`).
- **Short of Coal:** a research tile says so ("No stockpile in range has 100 F · 150 I · 75 C for Arms I"). A Dragon is refused with "No Keep in range has 160 F, 60 I and 25 C for a Azure Dragon."
- **Tooltips:** tiles show the Coal as "C".

**Knights trains** burn 0.08 Coal a metre (was 0.05; `assets/economy/fuel_knights_train.tres`). A full 60-Coal tank now runs 750 m.

**Building costs** can carry Coal too (`plan_spec`'s `coal`, from `ProductionBuildingStats.coal_cost`). A plan then shows it, needs it in range and takes it when it's built. No building costs Coal yet.

## Stoke Brazier (Z)

A toggle on the Chapterhouse's, Dragon Yard's and Forge's cards (`can_stoke_brazier` on their `.tres`). The Cyborgs' buildings have none.

**While it is on and the building works** (training a unit, or researching):
- the work goes `stoked_speed` (1.6x) as fast;
- it burns 1 Coal from the paying Keep every `brazier_coal_interval` (4 s). Each Coal is taken as the last one burns out, so the first is taken at once.

**Example:** a 15 s Round Table Marine takes 15 / 1.6 = 9.375 s and burns 3 Coal (at 0, 4 and 8 s).

**With no Coal** the work goes on at 1x and the queue is kept.
- The status reads "Brazier unlit · needs Coal".
- It lights again as soon as the Keep has Coal.
- If the Coal runs out partway, the rest goes at 1x. A Marine with 1 Coal takes 4 s at 1.6x (6.4 s of work), then 8.6 s at 1x: 12.6 s.

**Idle or off:** an idle building burns nothing. Paid time left over carries to the next job.

**The tile and status.**
- The tile reads "Stoke Brazier: on/off".
- Its tooltip says what it does and whether it burns now ("Burning: 1.6x speed", "Unlit: no Coal in the paying Keep", "Lit while it works", "Off").
- The building's status line and the HUD's progress line add "· Brazier lit" or "· Brazier unlit · needs Coal". A research's "s left" counts the faster pace while the Brazier burns.
- Pressed with several of the same building selected, it turns them all to the first one's opposite.

**Where it lives.** The numbers are on `ProductionBuildingStats` (`stoked_speed`, `brazier_coal_interval`). The burning is `ProductionBuilding.brazier_scale`, which the Forge's research uses too (`temple_of_science.gd`). The card art is `sl_stoke_brazier.png`, rendered from the Forge by `render_hud_images.gd -- forge_brazier`.

**Not in this item:** the handoff also names a pitched Hearth-Wain as a payer. That comes with the Hearth-Wain in item 6; for now the paying Keep is the payer.

## Lakeside Farms

A Farm with lake water within `lakeside_water_distance` (8 m) of its field's edge is **lakeside**. It gives `lakeside_food_per_beat` (3) Food a work beat, against 2 inland (`assets/economy/knights_rules.tres`).

- **When it's decided:** once, when the Farm is built (`farm.gd`, `Farm.lakeside_at`). The distance is measured straight from the field's nearest cell.
- **Label and panel:** "LAKESIDE FARM · 3 Food/beat"; the panel's Food a beat shows 3.
- **Placement preview:** placing a Farm where it would be lakeside adds "· Lakeside bonus: +50% Food".

## AI

`scripts/ai/knights_player.gd`; see `docs/KNIGHTS_AI.md`.

**Coal Mine sooner.** Home gets its Coal Mine and coal hand once a second Keep, a Forge or a Dragon Yard is started (standing or planned), not only once trains run (`coal_economy`).

**How much Coal it gathers** (`coal_target`). It works the mine while home holds less than half the target, and stops at the target. The target is the larger of:
- the trains' 120 (twice `train_coal_wanted`);
- the next Forge research's Coal plus `brazier_coal_above` (100). With Arms I next that is 175.

**Braziers** (`_braziers`): it lights the Braziers of its Chapterhouses, Dragon Yards and Forges while the Keep paying for each holds more than `brazier_coal_above` (100) Coal, and puts them out at or below it.

**Research** waits for its Coal like any other cost; Sundering Lances already waited for home's Coal (item 3).

## Checks

`tests/knights_coal_and_lakeside_test.gd` (headless, in the suite) checks:
- **Data:** all the Coal prices, Slow's new iron, the Brazier's numbers on the three buildings and none on the Cyborgs', and the lakeside rules.
- **Forge:**
  - Arms I waits without Coal ("75 C");
  - it takes 75 from the Keep.
- **Dragon Yard:**
  - a Dragon is refused without Coal;
  - it takes 25 Coal.
- **Brazier:**
  - with no Coal, a Marine takes 15 s and the status says "Brazier unlit · needs Coal";
  - with 1 Coal it takes 12.6 s;
  - with plenty it takes 9.375 s, burning 3 Coal, with "Brazier lit";
  - switched off, 15 s and nothing burnt.
- **Lakeside, on Two Lakes:**
  - a Farm by a lake gives 3 a beat and reads "LAKESIDE FARM · 3 Food/beat";
  - an inland one gives 2;
  - the placement preview names the bonus by the lake and not inland.
- **AI:**
  - no coal work with one Keep and nothing else;
  - a Coal Mine once it has a Forge;
  - a target of 175 with Arms I next;
  - Braziers lit at 150 Coal and out at 100.

Existing tests updated:
- `command_cards_test`: 82 tiles;
- `upgrades_test`: Arms I takes 75 Coal, and the Mail tile shows its Coal;
- `mist_slow_test`: Slow 100 F / 125 I / 75 C;
- `ai_upgrades_test`: home holds Coal for Arms I and Mail I;
- `knights_rail_test`: 100 m burns 8 Coal (was 5).

## Not done

- **Hearth-Wain as payer:** a pitched Hearth-Wain doesn't pay for the Brazier yet. It comes with the Hearth-Wain (item 6).
- **No flame:** the Brazier has no flame or smoke on the building models. Only the tile and status show it.
- **Coal economy in play:** the AI's earlier Coal economy hasn't been watched over a whole match.
- **Not played by a person:** none of this has been played by a person.
