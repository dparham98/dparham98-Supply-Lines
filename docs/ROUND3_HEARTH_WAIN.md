# Round 3: the Hearth-Wain, Forward Farms and the Living Draught

Item 6 of the Round 3 balance handoff (2026-11-25). Stacked on item 5 (`docs/ROUND3_KNIGHTS_COAL.md`).

The Knights get a field supply wagon and a new way to refill their Sentinels:
- **Keeps stop refilling Grail Sentinels.** A Sentinel refills on a working Farm, beside a pitched Hearth-Wain, or beside a Food crate.
- **The Hearth-Wain** is trained at the Dragon Yard. Pitched, it is a small Keep in the field: it pays for plans, takes drop-offs and lets Farms stand and work in its range (Forward Farms).

## Grail Sentinel refill

**A Keep never refills the reserve now** (`MedicalWork.refill_tick`). The reserve refills, healing or not, from the first of these the Sentinel has:

| Source | Where | Rate | Cost |
| --- | --- | --- | --- |
| **Living Draught** | On a working Farm, or within 3 m of its field | 15 points a 1.2 s beat | 1 Food off the Farm's next payout for each Sentinel that drew that beat |
| **Pitched Hearth-Wain** | Within 9 m of it | 10 points every 0.8 s (12.5 a second) | 1 Food from its hold for each 10 points: loose Food first, then Food crates aboard |
| **Food crate** | Within 4 m | 8 points (was 5) each second | 1 Food from the crate |

- **A working Farm** is one that is tilled by its Farmer, not raided, and covered (below). An unmanned, raided or dormant Farm gives nothing.
- **The Farm's payout:** two Sentinels drawing on a Farm that gives 3 a beat leave 1 for its Farmer's next beat. The payout never goes below 0.
- **Labels:** while a Sentinel draws on it, the Farm's label adds "· Provisioning Grail".
- **Dry:** a dry Sentinel says "Medical reserve empty · refill at a working Farm, Hearth-Wain or Food crate".

**Where the numbers live:**
- the Draught and the Wain's refill are on `assets/economy/knights_rules.tres` (Hearth-Wain and Living Draught groups);
- the crate's refill is on the Sentinel's scene (`med_refill_points`).

## The Hearth-Wain

A barded draught-steed and wagon, trained at the **Dragon Yard (H)**.

**Stats:**

| Cost | Time | Housing | HP | Speed | Sight |
| --- | --- | --- | --- | --- | --- |
| 60 F, 35 W, 20 I | 16 s | 1 | 110 | 5.5 m/s | 22 m |

It burns no fuel.
- **Data:** `assets/units/hearth_wain.tres`; its hold is `assets/economy/hearth_wain_rules.tres`.
- **Scene and script:** `scenes/gameplay/hearth_wain.tscn` and `scripts/economy/hearth_wain.gd`, a Cargo vehicle.

**On the move** it is a Cargo vehicle with a 100-unit hold, four crates of Food, Wood, Iron or Coal.
- **Hauling:** it loads, unloads, takes crate manifests and runs routes between Keeps and other pitched Wains, as a Cargo truck does.
- **Not a vehicle:** with no fuel, it isn't a "vehicle" to the repair and heal rules. Sentinels heal it; workers don't repair it.

**Pitch Hearth (D).** Pitching takes 2 s, and packing up takes 2 s. Pitched, it is a Knights supply source of `hearth_radius` (15 m) that spends **only from its hold**. Within that range:
- **Plans:** a Knights plan is paid from its hold with nothing carried, as a Keep's plans are (`ConstructionPlan.stock_keep`; a Keep first when both cover it).
- **Buildings:** a Chapterhouse, Dragon Yard or Forge can draw its costs and its Stoke Brazier's Coal from the Wain.
  - `ProductionBuilding.covering_depots` lists pitched Wains after the Depots.
  - The Brazier takes its Coal from the building's payer while that has Coal, else from the first covering Keep or Wain that has some.
- **Drop-offs:** workers drop off there. A Farmer takes her Food to the nearest receiving Keep or pitched Wain.
- **Farms:** Farms may stand and work in its range (below).
- **Sentinels** within 9 m refill from its Food (above).

**The HUD.**
- **Name:** it's named "Hearth-Wain".
- **Status:** "HEARTH-WAIN · HP · Hearth pitched".
- **Cargo line:** "F / W / I / C".
- **Card:** the Cargo card with "Pitch Hearth" / "Pack up the Hearth" on D and no Worksite tile.
- **Art:** its icon, portrait and Dragon Yard card are rendered from a placeholder model of boxes (`scenes/models/hearth_wain_model.tscn`, `render_hud_images.gd -- hearth_wain`). The canvas hood takes the team's colour.

## Forward Farms

A Farm works only while a living friendly Keep or a pitched friendly Hearth-Wain covers its centre (`Farm.covered`).

- **Placing it:** a Farm plan must stand in a Keep's range or a pitched Wain's.
  - The notice reads "A Farm must stand inside one of your Keeps' range or a pitched Hearth-Wain's."
  - The preview is red elsewhere.
- **Dormant:** uncovered (its Wain packed up, moved off or dead), it pays nothing and gives no Draught. Its label reads "Dormant · needs Keep or Hearth-Wain in range".
  - Its Farmer stays its worker, so it works again as soon as a Keep or Wain covers it.
  - She may also take another empty Farm, since a Farmer is only held to a Farm that still works.
- **Lakeside:** a Forward Farm by a lake is a Lakeside Farm (item 5): 3 Food a beat.

## AI

`scripts/ai/knights_player.gd`; see `docs/KNIGHTS_AI.md`.

**Sentinels refill at a Farm.** A Grail Sentinel that is out of a wave goes and stands on the nearest working Farm when either:
- its reserve is below `sentinel_refill_below` (40%);
- or it is wounded below `sentinel_wounded_below` (50%) with its reserve not full.

**While it refills:**
- **Held off the rally point:** fight() neither calls it back to the rally point nor takes it into a new wave. The hook is `EnemyPlayer.kept_off_rally`, which only the Knights use.
- **Defence:** a threat at home still calls it to fight.
- **Let go:** once its reserve is full it is let go and goes back to the rally point.

**No working Farm:** it stays where it is.

The AI doesn't train Hearth-Wains yet.

## Checks

`tests/hearth_wain_and_forward_farm_test.gd` (headless, in the suite) checks:
- **Living Draught** (Arthurian skirmish):
  - a Keep gives nothing;
  - an unmanned Farm gives nothing;
  - a manned one gives two Sentinels 15 points a beat each, and its next payout is 2 Food short, then whole again;
  - the label says "Provisioning Grail";
  - a raided Farm gives nothing, and neither does a Farm more than 3 m off.
- **Hearth-Wain** (Two Lakes, Knights at home):
  - the Dragon Yard takes 60 Food and trains it in 16 s;
  - a Farm plan beyond every Keep's range is refused;
  - the Wain drives about 130 m to the nearest lakeside field beyond the Keep's range and pitches in 2 s;
  - a Maiden builds the Farm from the Wain's wood (30) and works it as a 3 Food/beat Lakeside Farm. The Food goes into the Wain, not the Keep;
  - a Sentinel 4 m from the Wain refills 10 points for 1 Food;
  - packed up, the Farm pays nothing, gives no Draught and reads "Dormant".
- **AI** (Two Lakes, Knights as the AI):
  - a full Sentinel stays;
  - one at 30 goes to the Farm;
  - fight() leaves it there;
  - it fills on the Farm;
  - once full it is let go and sent to the rally point.
- **Data:** the Wain's price, its Dragon Yard tile and the Knights rules.

**Existing tests updated:**
- `arthurian_faction_test`: no Keep refill; a Food crate gives 8 points;
- `command_cards_test`: 83 tiles;
- `knights_coal_and_lakeside_test`: a lakeside Farm with no Keep over it pays nothing.

## Not done

- **Roads:** the handoff's 7.5 m/s on Roads waits for item 7.
- **Boarding transport:** a Farmer with a dormant Farm can't board transport. That is item 7 too.
- **Repairs:** the Wain pays no repairs. The handoff's "1 W + 1 I" Knights repair isn't in the game; Knights repairs are paid as before.
- **AI Wains:** the AI doesn't train or pitch Hearth-Wains.
- **Model:** the model is a placeholder. It has no animation, and no camp or fire shows when it's pitched.
- **Not played:** none of this has been played by a person.
