# Knights rail

Item 13 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. The owner chose coal as the train's fuel. Every number is a play-test starting point, kept in `assets/economy/knights_rules.tres` (group Rail) unless noted.

## Dragon Yard

Asked for on 2026-11-25: the Wainwright is gone, and the Knights' vehicles and dragons come from one production building, the **Dragon Yard**. It is Y on the Build page (`scenes/gameplay/dragon_yard.tscn`, `assets/buildings/dragon_yard.tres`):
- **Cost:** 60 W / 60 I, from a covering Keep's stock, else delivered to the site, as the Chapterhouse.
- **Size and place:** 6 × 6, inside one of your Keeps' range, as a Farm.
- **What it makes:** the **Azure Dragon** (D), which the Chapterhouse no longer raises, and the coal **Train** (T, below). Its card works like the Chapterhouse's: it pays from a covering Keep, and the Dragon takes housing.
- **What it allows:** while one stands, the side may lay track from its Keeps.

  If every Dragon Yard falls, laid track and trains keep working, but no new track or trains can be bought.
- **Model:** for now the Wainwright's model (docs/WAINWRIGHT_MODEL.md) stands in. The art session is making a Dragon Yard model.

## Track

The same maglev track the Cyborgs lay (`docs/RAIL_PLANNING.md`), at the same price: 2 iron a metre (`rail_iron_cost`). The Knights' Rail tile shows on the Build page once a Dragon Yard stands.

**Who pays:** a Keep's iron, through the same rules as a Depot (`RailNetwork.can_place`, `plan_payer`, `wreck_payer`). `KnightRail.may_pay` stops a Keep from paying while its side has no Dragon Yard.

**No energy:** track costs no energy, and the line's upkeep is drawn only from Depots' energy, so Knights lines pay none. A line joined to a Keep shows as live (cyan) without energy, because its trains run on coal.

## Train

Ordered from the Dragon Yard card's **Train** tile (T). It is built at, paid by and leaves from a friendly Keep whose range covers the yard and has friendly track in its loading area, the yard's own paying Keep first (`KnightRail.train_keep`). With none, the tile is greyed out and says to lay track into such a Keep first. The Keep's card has no Train tile.
- **Cost:** 60 F / 40 W / 30 I. Cancel refunds it.
- **Build time:** 30 s.
- **Scene:** `scenes/gameplay/knights_train.tscn`, the Cyborg train with `coal_fuelled` on.
- **Speed:** 12 m/s (`assets/economy/knights_train_rules.tres`; the Cyborg train runs at 16).
- **Capacity:** 300.

When a Keep has several lines, the player clicks the line to start on, as at a Depot.

**Fuel** (`assets/economy/fuel_knights_train.tres`):
- **Burn:** 0.05 coal a metre from its own 60-coal tank, so a full tank runs 1200 m. It draws no Depot energy.
- **Running out:** an empty train stops: "Out of coal · refuel at a Keep".
- **Refuelling:** stopped, it refuels at 5 coal a second from a covering Keep's or Depot's coal, a deployed Cargo truck's coal, or a coal crate beside it, as other vehicles do (`docs/FUEL_BATCH.md`).
- **Maps without vehicle fuel:** it burns nothing.

**Cargo:** it carries and runs routes like the Cyborg train, between friendly Keeps or Depots: Energy, Iron, Wood and Coal.

## Decided here

- **The Keep's menu:** the handoff's "Decided" list says the Keep's menu has no truck, train or track. Since 2026-11-25 the train is ordered from the Dragon Yard, so the Keep's menu has none again; the Keep is still where the train is built and leaves from.
- **Coal per metre:** 0.05 a metre (a third of the Cyborg vehicles' 0.15), with a 60 tank. The handoff gave no number.
- **Build time:** 30 s. The handoff gave no number.
- **Keeps only:** the Dragon Yard enables track and trains at Keeps only. A Cyborg Depot captured by the Knights works as it always has.
- **Art:** the Knights train has its own model (docs/KNIGHTS_TRAIN_MODEL.md) and card (`sl_produce_knights_train.png`). The Dragon Yard borrows the Wainwright's model and card until its own are made.

## Not done

- **Food:** a train can't carry Food. The route and Load page know Energy, Iron, Wood and Coal only. Food still moves by balloon and crates.
- **AI:** the Knights AI builds a Dragon Yard once it has a second Keep, joins its Keeps with track, runs trains hauling iron home, and builds a Coal Mine for their fuel (`docs/KNIGHTS_AI.md`, Rail; `tests/ai_knights_rail_test.gd`).

## Check

`tests/knights_rail_test.gd` (headless) covers:
- the Chapterhouse no longer raising Dragons;
- no track and no train before a Dragon Yard;
- the Dragon Yard's plan spec and its Dragon;
- the yard's train going to the covering Keep with track, and its card tiles;
- track at 2 I a metre from the Keep;
- the train's cost, its refund and its build;
- 12 m/s;
- 5 coal per 100 m;
- stopping when empty and refuelling from the Keep's coal;
- the Keep card and Build page tiles.
