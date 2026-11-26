# Vehicle repair

Asked for on 2026-11-19: Infantry could repair buildings but not vehicles.

- **Who repairs:** any unit that can repair buildings (`can_repair`, the Infantry). It repairs your vehicles the same
  way: right-click a damaged one, or use the Repair card (R) and click it. A unit never repairs itself.
- **What counts as a vehicle:** a unit with fuel rules: Tank, Derailer, Drone, Ubermech, Depot truck, Cargo truck and
  trains. Infantry, Grenadiers and Scouts are people and are not repaired.
- **Only your own:** enemy vehicles are not repaired. Mines stay repairable by any side, as before.
- **Rate and cost:** the building rules in `assets/economy/engineering_rules.tres`: 10 HP every second for 2 E and
  1 I, within 7 m.
- **Knights repairs** (2026-11-25, item 1 of the Round 3 handoff): a Keep holds no energy, so a repair paid by a Keep
  (or a pitched Hearth-Wain, once it exists) costs **1 Wood and 1 Iron** a tick instead (`repair_wood`). Before, a
  Forester Maiden repairing anything from a Keep stalled at "local funds unavailable".
  - A Farm, House or Railhead has no wallet of its own: it is repaired from the nearest friendly Keep covering it.
  - The Keep itself, and the Chapterhouse, Forge and Dragon Yard, are paid by their Keep as before.
- **Who pays:** a Depot or deployed Cargo truck whose range covers both the repairer and the vehicle, nearest first.
  A deployed truck pays its energy by burning coal, as for building (docs/MOBILE_SUPPLY.md). With no stockpile in
  range the repair waits.
- **A vehicle that moves** is followed; repair resumes once it is in reach again.
- **Right-click priority:** a worker bringing cargo to a deployed Cargo truck still unloads into it; with nothing to
  unload it repairs the truck if it is damaged.

## Code and checks

- `EngineeringWork.is_vehicle`, `repairable`, `payer_for` and `tick` in `scripts/economy/engineering_work.gd`;
  `command_repair` and `_repair` in `scripts/gameplay/unit_agent.gd`; `pick_vehicle_to_repair` and its uses in
  `issue_order` and `issue_card_order` in `scripts/gameplay/skirmish.gd`.
- `tests/vehicle_repair_test.gd` (headless) covers a Depot paying for a Tank at the building rate, following a Tank
  that moves, refusing Infantry and an enemy Tank, waiting out of range, a deployed Cargo truck paying, and
  right-click and the Repair card ordering it.
