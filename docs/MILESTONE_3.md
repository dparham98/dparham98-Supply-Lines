# Milestone 3: local power and explicit supply

UI update: the old side panels are replaced by the bottom selection HUD. Select a Depot for production, infantry → Build for local construction, and a cargo vehicle for delivery routes. See BOTTOM_HUD.md; the economy rules below remain applicable.

Testing override enabled: every Depot now spawns with 500 iron, including initial, neutral, directly built and truck-deployed Depots. This is a one-time grant, not regeneration or sharing. Set Testing Starting Iron to -1 in assets/economy/depot_rules.tres to restore all normal scenario/instance/construction inventories described below and the economy regression fixtures. Energy and costs are unchanged.

Open scenes/maps/supply_routes.tscn and press F6 for the new exercise. F5 still opens the original skirmish; its camera, original actors, terrain, unit stats and fallback combat are retained. The exercise inherits that scene and adds an empty friendly Outpost, a neutral Depot and one cargo vehicle. It starts the main Depot with 500 energy / 200 iron so supply can be tested immediately. These are authored scenario grants; normal skirmish still starts with 500 energy / 0 iron.

## Quick editor test

1. Select the starting Depot. The right panel shows local stock and territory; the left panel shows its generation rate. Click Build generator, then click green preview land inside the Depot ring. It costs 100 energy / 20 iron and supplies only that Depot at 5 energy/second. Esc cancels. Red preview means terrain, occupancy, territory, ownership or funds prevent placement. Cost and payer appear over the footprint.
2. Select the yellow tracked cargo placeholder near the starting Depot. In the left panel select From Depot = Depot, To Depot = Outpost. Keep energy = 60 and iron = 40 (combined capacity 100). Click Assign route to selected cargo. Resources remain at the source while it approaches and loads; after 2 seconds at the source they become vehicle cargo. They credit the Outpost only after travel and 2 seconds unloading. Inspect each Depot by clicking it; select the vehicle again to inspect cargo and route status.
3. Repeat the delivery once, or enable Repeat this route before assigning it. The Outpost receives 120 energy / 80 iron after two full deliveries. Select it, build a generator inside its territory, wait for energy, and print infantry there. That completes the outpost supply → local generation → local production loop. You can instead deploy a Depot Truck and choose its new Depot in the endpoint menus.
4. Test one-off delivery (Repeat unchecked), then repeating delivery. Pause/Resume stops and restarts the selected vehicle's route. Cancel retains its cargo. A manual right-click move cancels the route and retains cargo too. Assign a new route explicitly to deliver held cargo; it unloads that load first, without loading twice.
5. Move infantry within 12 units of NeutralDepot for 8 uncontested seconds to capture it. It then appears in friendly endpoint menus. To test capture interruption, author an enemy unit near a supply endpoint, move friendly defenders out, and let it capture while cargo is in transit. Both source and destination ownership changes pause a route immediately, including if ownership later returns before the next vehicle tick. It remains paused after recapture until you explicitly resume. A lost or removed endpoint never receives cargo; invalid resume reports a message. Reassigning friendly endpoints is an explicit way to redirect held cargo.
6. Check construction outside territory, occupied footprints, poor selected Depots in overlapping territory, insufficient cargo stock, blocked paths and cancelled routes. Check original gather/print/fight gameplay, camera rotation/zoom, arrow movement and screen-edge scrolling. The supply exercise keeps the original gather/print/kill victory banner; logistics completion is a manual test goal, not a new win condition.

## Provisional editable rules

New defaults are prototype balance decisions, not recovered historical specifications. Edit assets/economy/supply_rules.tres in Inspector; restart play after changing shared settings.

| Setting | Default |
| --- | --- |
| Generator construction | 100 energy / 20 iron |
| Generator footprint | 3 × 3 cells |
| Local generation | 5 energy/second, no storage cap or upkeep |
| Cargo vehicle production | 100 energy / 20 iron, existing 3-second Depot queue |
| Cargo capacity | 100 total energy + iron units |
| Cargo speed / HP | 4 world units/second / 80 HP |
| Loading and unloading | 2 seconds each, uninterrupted while within Depot dropoff range |

Generator placement uses the selected friendly Depot as sole payer and recipient, with all footprint corners in its construction radius and all cells empty/buildable. No neighbour can pay or receive its generation implicitly. Assignment is fixed at construction; generators have the constructing team's ownership. They stop when their assigned Depot is removed or belongs to another team; they resume generation if that Depot returns to the original team. They never search for another recipient. Multiple generators add their output; fractional energy is accumulated per generator so frame rate does not discard fractional output. Buildings still have no damage/destruction gameplay. No energy sharing, range transmission or upkeep is implied.

Routes require two distinct friendly Depots and positive, nonnegative per-trip maxima with a combined total at or below capacity. They carry separate energy/iron quantities. At loading completion each resource loads up to its requested amount and current available stock; unavailable amounts are not borrowed or fabricated. An entirely empty load waits and retries every transfer interval, even on one-off routes. Partial loads depart. After delivery, a repeating route returns to its explicitly chosen source; a one-off route finishes. Nothing moves between Depots without an assigned route. Cargo is deducted exactly once at load and credited exactly once at unload. No stock is reserved during travel toward the source; competing spending/loading sees current balances.

Capture of either endpoint pauses the route, releases movement reservations beyond the current cell and resets transfer progress. Cargo stays on the vehicle, including during pause/cancellation/manual move. Resuming requires the original two endpoints to be friendly. A newly assigned route is an explicit player choice and can redirect held cargo. A destroyed cargo vehicle loses its carried resources permanently; there is no refund, salvage or automatic return. An invalid/deleted endpoint pauses safely. A blocked route waits and retries existing terrain paths, without teleporting, crediting or switching destination. Vehicles cannot gather, shoot, establish Depots or contribute to capture; they can be attacked. If multiple cargo vehicles are selected, the supply panel operates on the first in selection/group order, one vehicle per action.

Direct-built Depots remain empty at creation and truck-created Depots keep Milestone 2 starter stock. Supply now lets you bootstrap empty outposts. The defeat check recognizes friendly generators that can replenish enough energy for infantry when that Depot already has enough iron. There is no loss-of-supply victory condition. Unresolved infantry combat notation and all seven unit resources are unchanged.

## Files and architecture

SupplyRules contains balance only. Generator instances own fractional output and bind one Depot. CargoVehicle extends the existing gameplay unit controller and calls its original occupancy, waypoint and path methods. Its route and carried quantities are instance state. Depot printing recognizes cargo as another prepaid queue entry. Depot ownership_changed signals pause active routes immediately. Construction uses saved preview/model scenes; scripts move/color these instances without generating actor meshes or UI. The left supply panel and generator/cargo placeholders are authored scenes and visible in the editor. Unit Visuals model slots remain replaceable; the Blender infantry is not imported by this milestone.

Edit scenes/gameplay/energy_generator.tscn and scenes/gameplay/cargo_vehicle.tscn for model slots; scenes/models/*_placeholder.tscn for native placeholder geometry; scenes/gameplay/construction_preview.tscn for ghost appearance; scenes/ui/skirmish_hud.tscn for controls; scenes/maps/supply_routes.tscn for exercise actors. A scenario-authored generator must be on exact empty buildable land and have Assigned Depot Path set; runtime-built generators receive their assignment explicitly. Organizational scene parents remain untransformed, as required by the existing project navigation.

Exact changed files: MILESTONE_3_CHANGED.txt. Before-change copies for existing authored files are in the chat workspace milestone3_before. Godot's ignored .godot cache is excluded. See MILESTONE_3_VALIDATION.md for executed checks and limitations. Milestone 2's documentation describes the previous finite-energy/no-logistics state; this document supersedes those limitations while preserving its capture and local spending rules.
