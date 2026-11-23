# Arthurian Knights faction

The second faction, alongside the Cyborgs.

**Origin:** made on 2026-11-22 with another tool, directly in the local checkout, where it was left uncommitted. The
same day it was moved onto its own branch from main and merged onto main's newer code.

**Where it plays:**

- **Two Lakes, from the main menu:** choose Arthurian Knights for You, against the AI or with no opponent. Your West
  start becomes a Keep with two Forester Maidens (docs/MAIN_MENU.md). The AI can't play the Knights.
- **The showcase map,** `scenes/maps/arthurian_skirmish.tscn` (open it and press F6).

## Buildings

| Building | What it does |
| --- | --- |
| Keep | The faction's base. It stores Food, Wood and Iron; trains Forester Maidens (F) and Warhounds (W); packs Food, Wood and Iron crates (C). It is a kind of Depot (`scripts/gameplay/keep.gd` extends `depot.gd`). |
| Chapterhouse | Trains Round Table Marines (R), Grail Sentinels (G), Questing Marines (Q) and Azure Dragons (D). Its model is still a placeholder. Costs 40 Food, 30 Wood and 40 Iron. |

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
| Round Table Marine | 65 | 25 | 65 | Range 16 |
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

- 5 HP a second, for 1 Food from a covering Keep.
- Away from a Keep it uses a carried reserve of 120 HP. There is no free regeneration.
- It refills the reserve at a Keep or beside a Food crate.

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

These come from the original report:

- **A Farm:** the Forester Maiden's model already has a sun hat, a farming tool and a Till clip.
- **An Air Balloon** from the Keep's roof pad: `keep.launch_balloon_fx()`.
- **A Chapterhouse model.**
