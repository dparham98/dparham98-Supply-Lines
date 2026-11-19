# Bastion with a close-defence turret

The roof turret tracks and engages the nearest hostile unit within 10 game metres. Its gun can turn through 360° while the main cannon tracks a different target. When aligned within 3°, the roof gun launches a solid copper-tipped bullet from its muzzle. The bullet travels straight at 18 game m/s and deals 3 direct damage on impact. A target can move clear before it arrives. Range, damage and the 0.35 s cooldown are editable on the actor's `CloseDefense` component. The main cannon keeps its existing 30 m range and its own orders and reload cycle.

[Watch the bullets in flight at half speed](preview/bullets.webp) · [Watch the turret traverse](preview/traverse.webp) · [Godot range](validation/Bastion_AutoTurret_Review.zip) · [Editable Blender source](source/Bastion_AutoTurret.blend) · [Tank GLB](export/Bastion_AutoTurret.glb)

Extract the range ZIP outside Supply Lines and open `project.godot` with Godot 4.7.2. Press **F5** to start, **Tab** to inspect the roof and **Space** to move the near target in or out of range. You can also click the ground to set a new bearing. The range directs the main gun at a distant target and uses the variant's actual controller for the roof gun.

## Playable actor

The separate variant uses the existing tank actor and visuals wrapper. To stage it in a disposable copy of the game, run the following from the working checkout, passing the copy's project directory. Instance `res://bastion/bastion_tank.tscn` there. Its `CloseDefense` child owns the auxiliary shots. The GLB alone provides the editable geometry, a traverse pivot and a muzzle marker.

```powershell
python Blender/Vehicles/Tank/Astra_Bastion/AutoTurret/gameplay/stage_actor.py C:/path/to/disposable-game
```

The hatch carries a stationary bearing, the rotating receiver and its barrel. The exporter verified clearance at 360 sampled bearings, with the lowest rotating surface 0.057 world m above the original Bastion. The three additional meshes add 732 triangles and bring the tank to 7,412. The original 43 meshes retain their geometry and material assignments.

## Verification

On the First Contact map the roof gun launched 23 discrete bullets. The first traveled 7.32 game metres and hit after 0.40 seconds. Targets that dodged or became friendly before impact took no damage. The actor engaged two targets 89.29° apart, and the roof gun scored four hits during the main reload. Main cannon, rolling tracks and all three death sequences passed their existing regressions. [Measured results](validation/combat.json)

The variant is isolated for review. Its new combat tuning awaits a player balance test.
