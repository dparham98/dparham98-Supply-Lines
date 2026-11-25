# Arthurian Knights faction

The second faction, alongside the Cyborgs.

**Origin:** made on 2026-11-22 with another tool, directly in the local checkout, where it was left uncommitted. The
same day it was moved onto its own branch from main and merged onto main's newer code.

**Where it plays:**

- **Two Lakes, from the main menu:** choose Arthurian Knights for You, against the AI or with no opponent. Your West
  start becomes a Keep with two Forester Maidens (docs/MAIN_MENU.md). The Knights AI (docs/KNIGHTS_AI.md) can play either start.
- **The showcase map,** `scenes/maps/arthurian_skirmish.tscn` (open it and press F6).

## Buildings

| Building | What it does |
| --- | --- |
| Keep | The faction's base. It stores Food, Wood and Iron; trains Forester Maidens (F) and Warhounds (W); packs Food, Wood and Iron crates (C); and launches an Air Balloon (L) that flies up to four of those crates to a point (`docs/AIR_BALLOON.md`). It is a kind of Depot (`scripts/gameplay/keep.gd` extends `depot.gd`). |
| Chapterhouse | Trains Round Table Marines (R), Grail Sentinels (G), Questing Marines (Q) and Azure Dragons (D). Costs 40 Food, 30 Wood and 40 Iron. |

**Founding a Keep:** Build (B) → Keep (K) plans a Keep anywhere on valid land.

- It needs 50 wood and 50 iron delivered to the site, and no payer or covering range.
- It keeps the Depot spacing.
- It has no Depot Truck strip.
- A Forester Maiden builds it.

## Units

| Unit | Food | Iron | Health | Notes |
| --- | --- | --- | --- | --- |
| Forester Maiden | 45 | 0 | 45 | Worker: gathers and builds |
| Warhound | 30 | 5 | 38 | Melee |
| Round Table Marine | 65 | 25 | 65 | Range 18 |
| Grail Sentinel | 75 | 20 | 75 | Heals; range 10 |
| Questing Marine | 75 | 35 | 65 | Range 19 |
| Azure Dragon | 160 | 60 | 180 | Breath; its Breath_Light shows only while breathing |

## Mechanics

**Food:** a new resource, alongside energy, iron, wood and coal. It is in stockpiles, crates, piles, the crate pips,
the map overlay and cargo. Units and buildings can now cost Food and Wood (`food_cost`, `wood_cost`).

**Labour:** a site's labour is paid in Food when its spec costs Food, else in energy (`labor_kind`, `labor_cost`).

**Who pays for production:** a production building picks its payer as on main: the one it has while that one can
pay, else the nearest covering one that can. A covering Keep counts. The check includes Food and Wood (`payer_for`).

**Healing (Heal, H):** the Grail Sentinel heals friendly units that aren't vehicles.

- **Healing:** 10 HP a second, at up to 9 m.
  - **Reserve:** it always heals from a carried reserve of 200 points, one point for one HP. There is no free regeneration.
  - **By itself:** idle or attack-moving with reserve left, it heals the most hurt friend within 9 m (lowest share of its health). After that, it carries on with the attack-move.
- **Refill:** the reserve refills only inside a friendly Keep's range or beside a Food crate, 5 points for 1 Food each second, whether or not it is healing.
  - The refill is data on the Sentinel's scene (`med_refill_kind`, `med_refill_cost`, `med_refill_points`, `med_refill_interval`). A cost of 0 makes it free, which the owner is weighing.

These are item 6 of the balance handoff (2026-11-25). Before that it healed 5 HP a second at 7 m, only when ordered, with a 120-point reserve. Inside a Keep's range it was paid straight from the Keep's Food.

Item 6's battle check is `tests/knights_line_battle_sim.gd`. It isn't in the suite; run it with `--fixed-fps 30`.

The code is `scripts/economy/medical_work.gd`.

**Team paint:** team surfaces now also take a shadow paint (`team_color_shadow` and the three `*_shadow` materials).

## Merged onto main

These are the conflicts with main's newer code, and how they were settled:

- **Plans keep their own team**, and still need sight. Keep plans keep the Depot spacing check.
- **Production pays from a picked payer:** `payer_for` also checks Food and Wood, and the message names a Keep when
  Food is short.
- **Labour that energy pays counts a deployed truck's coal** (`DepotNetwork.labor_stock`), as on main.
- **Wording:** main's Deforester wording, Temple of Science and Mining Trains are kept.
- **A site that owes no labour still takes a covering payer**, which a finished Generator is assigned to.
- **The HUD has ten more card tiles:** Keep, Chapterhouse, the Food crate, Heal and the six unit tiles
  (`tests/command_cards_test.gd` counts 62).

## Checks

`tests/arthurian_faction_test.gd` (headless) and `tests/arthurian_skirmish_runtime_check.gd` (rendered) were made
with the faction. The full headless suite runs on the branch.

## Next

All three items from the original report are now in: the Farm and House (Round 2), the Air Balloon (`docs/AIR_BALLOON.md`) and the Chapterhouse model.
