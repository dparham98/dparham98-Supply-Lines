# Wood/coal generator stage

Free generator energy has been replaced with fuel-backed conversion. The rates below are editable prototype values from ECONOMY_PLAN.md, not recovered original balance. Water mode remains pending a design decision.

## Implemented rules

| Mode | One completed cycle | Nominal rate |
| --- | --- | --- |
| Wood (default) | 1 wood -> 10 energy over 2 seconds | 5 E/s |
| Coal | 1 coal -> 50 energy over 5 seconds | 10 E/s |
| Either | Wood first; coal only when no wood is available at cycle start | Depends on selected fuel |

Coal yields five times as much energy per material unit, at twice the sustained generation rate. Defaulting to wood protects coal for future vehicle use. All modes use one whole material unit per cycle.

- Fuel and output belong to the same explicitly assigned friendly Depot. Generators have no separate inventory, loose fuel reserve, mobile operating wallet, automatic transfers or fallback payer. Construction costs remain 100 E / 20 I. Infantry and deployed train construction/explicit operating Depot assignment remain supported.
- A cycle starts only with the selected material present and room for the full 10/50 energy output. This intentionally requires 10/50 free units before conversion, even though withdrawing one fuel unit would make an extra slot. Full shared storage stops generation; carrying energy away or spending it frees capacity.
- Fuel stays in the Depot during the timer and is withdrawn only when the complete output can be deposited atomically. No partial energy is emitted. Other actors can transfer/spend the fuel during a cycle: generation then pauses until that material is restored, without creating energy or borrowing another type. Multiple generators competing for the last fuel unit cannot duplicate it.
- If storage fills during a cycle, elapsed work pauses and the fuel remains untouched. Freeing space resumes the remaining cycle time; blocked time is never accumulated for a later burst. Every completed cycle rechecks both fuel and storage. Normal long ticks can complete several backed cycles, with a defensive ceiling of 1,000 cycles per update; time beyond that ceiling is discarded rather than banked.
- Changing Wood/Coal/Either affects the next cycle. The current cycle keeps its original fuel, duration and output. Pause generator stops progress and consumption; Resume continues the pending cycle. If Either chooses wood and wood is removed during that cycle, it waits for wood; it does not switch that cycle to coal.
- Depot capture or destruction prevents output to an unavailable source. Capture resets unfinished work time; no fuel/output needs refunding because none was withdrawn. Reassigning to another covering friendly Depot also resets unfinished work and leaves all stock where it was. Generator destruction does not consume pending Depot fuel. Production/repair/capture rules elsewhere remain unchanged.
- The contextual HUD shows assigned local E/I/W/C stock and total capacity, operating/waiting reason, cycle progress, effective running rate, a fuel preference dropdown, Pause/Resume and Focus assigned Depot. Depot generation readouts count currently eligible fueled generators at the appropriate 5/10 E/s nominal rate. Waiting/full/disabled sources show zero.

## Editable resources and preserved behavior

assets/economy/generator_rules.tres supplies wood/coal outputs and durations. The generator scene assigns it through fuel_rules. Changes affect subsequent cycles; a started cycle retains its latched values. SupplyRules still controls construction footprint/cost and cargo values. Its old energy_per_second field is retained for Inspector compatibility only and no longer produces free energy.

The saved Generator placeholder, model slot and native HUD scene remain in use. No gameplay visuals are generated. Existing local stockpiles, 500-iron Depot test grant, one establishment Infantry, mobile deployment, trains/rails, piles, unit resources, combat fallback, camera/edge scrolling and pathing remain in place. No protected map textures/data or baked scenery changed.

Water generation, coal deposits/extraction, vehicle fuel consumption/refueling and Drone landing/emergency rules are not enabled. Coal in this exercise is authored test stock; it is not a new starting grant for ordinary Depots. Wood can now be harvested and stockpiled to power generators in ordinary play. Vehicle onboard fuel remains separate and inactive; generators never read it.

## Editor tests

1. Open scenes/maps/generator_exercise.tscn and press F6. It starts with a Generator assigned to the main Depot, 20 wood and 10 coal there, the existing 500 iron/500 energy, a second Depot and a train. The authored hostile is disabled. Generation begins using wood; select Generator to inspect its HUD.
2. Leave Burn wood selected: every two seconds, one wood disappears and ten energy arrives in its assigned Depot. Choose Burn coal: after any current wood cycle finishes, one coal produces fifty energy every five seconds. Choose Either to prefer wood. These are whole-cycle outputs, not energy added every frame.
3. Click Pause generator during a cycle and watch progress/stock stop. Resume and verify it completes the remaining time. If fuel runs out, it should display Waiting instead of producing free energy. Gather the nearby authored wood stand with Infantry and deliver it to the main Depot to restart wood generation.
4. Select Generator and choose EastDepot in Assign Depot. The unfinished cycle resets, and the original Depot keeps its stock. EastDepot starts without wood/coal, so the Generator waits. Deliver wood to EastDepot using Infantry, or explicitly transport fuel there by train; only that Depot then receives the generated energy.
5. To test full storage quickly, before running set the main Depot's initial energy to 1,470 in this exercise only: 500 testing iron + 20 wood + 10 coal + 1,470 energy fills its 2,000 capacity. Generator should pause without burning anything. Printing a Cargo Vehicle or assigning a train delivery that removes energy frees storage and allows generation. Restore the exercise override afterward, or restart from the saved original scene.
6. Ordinary play: build a Generator for 100 E / 20 I, harvest and deliver wood to its assigned Depot, then choose a fuel mode. Mobile-funded Generators wait for an explicitly assigned covering Depot as before.

Shared fuel, full/partial capacity, mid-cycle fuel removal, capture, destruction and assignment conservation are also tested headlessly. See GENERATOR_BATCH_VALIDATION.md and GENERATOR_BATCH_CHANGED.txt for validation and the exact file list. No live physical input testing was performed.
