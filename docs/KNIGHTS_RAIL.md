# Knights rail

Item 13 of the balance handoff (`docs/BALANCE_IMPLEMENTATION_HANDOFF.md` on the balance branch), 2026-11-25. The owner chose coal as the train's fuel. Every number is a play-test starting point, kept in `assets/economy/knights_rules.tres` (group Rail) unless noted.

## Wainwright

A Knights building, W on the Build page (`scenes/gameplay/wainwright.tscn`, `assets/buildings/wainwright.tres`):
- **Cost:** 60 W / 60 I, from a covering Keep's stock, else delivered to the site, as the Chapterhouse.
- **Size and place:** 4 × 4, inside one of your Keeps' range, as a Farm.
- **What it does:** while one stands, the side may:
  - lay track from its Keeps;
  - build trains at Keeps.

  If every Wainwright falls, laid track and trains keep working, but no new track or trains can be bought.
- **Model:** a placeholder (the House).

## Track

The same maglev track the Cyborgs lay (`docs/RAIL_PLANNING.md`), at the same price: 2 iron a metre (`rail_iron_cost`). The Knights' Rail tile shows on the Build page once a Wainwright stands.

**Who pays:** a Keep's iron, through the same rules as a Depot (`RailNetwork.can_place`, `plan_payer`, `wreck_payer`). `KnightRail.may_pay` stops a Keep from paying while its side has no Wainwright.

**No energy:** track costs no energy, and the line's upkeep is drawn only from Depots' energy, so Knights lines pay none. A line joined to a Keep shows as live (cyan) without energy, because its trains run on coal.

## Train

Built at a Keep with friendly track in its loading area: the Keep card's **Train** tile (T), shown once a Wainwright stands.
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

- **The Keep's menu:** the handoff's "Decided" list says the Keep's menu has no truck, train or track. This item adds a train and track to it once a Wainwright stands. That follows item 13 as you approved it; say if you want it the other way.
- **Coal per metre:** 0.05 a metre (a third of the Cyborg vehicles' 0.15), with a 60 tank. The handoff gave no number.
- **Build time:** 30 s. The handoff gave no number.
- **Keeps only:** the Wainwright enables track and trains at Keeps only. A Cyborg Depot captured by the Knights works as it always has.
- **Placeholders:** the House model for the Wainwright, the Cyborg train model for the Knights train, and the Rail and Train card art.

## Not done

- **Food:** a train can't carry Food. The route and Load page know Energy, Iron, Wood and Coal only. Food still moves by balloon and crates.
- **AI:** the Knights AI builds a Wainwright once it has a second Keep, joins its Keeps with track, runs trains hauling iron home, and builds a Coal Mine for their fuel (`docs/KNIGHTS_AI.md`, Rail; `tests/ai_knights_rail_test.gd`).
- **Art:** no models or card art of their own.

## Check

`tests/knights_rail_test.gd` (headless) covers:
- no track and no train before a Wainwright;
- the Wainwright's plan spec;
- track at 2 I a metre from the Keep;
- the train's cost, its refund and its build;
- 12 m/s;
- 5 coal per 100 m;
- stopping when empty and refuelling from the Keep's coal;
- the Keep card and Build page tiles.
