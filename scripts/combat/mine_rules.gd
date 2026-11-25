class_name MineRules
extends Resource
## Derailer minelaying (item 9 of the balance handoff, docs/MINES.md). Play-test starting points.

## Mines a Derailer carries once its side has researched Minelaying.
@export_range(0,20,1) var capacity := 2
## Iron one mine costs, taken where it is loaded: a friendly Depot whose range covers the stopped Derailer, or a
## deployed Cargo truck beside it.
@export_range(0,1000,1) var iron_per_mine := 10
## Seconds between loading one mine and the next, as a vehicle refuels a little at a time.
@export_range(0.1,30,0.1) var load_seconds := 1.0
## Seconds the Derailer works to lay one.
@export_range(0.1,30,0.1) var lay_seconds := 2.0
## Seconds after it is laid before it arms and is hidden.
@export_range(0,60,0.5) var arm_seconds := 3.0
## An enemy ground unit this near sets it off.
@export_range(0.5,10,0.1) var trigger_radius := 2.0
## Damage to the unit that set it off; others within `splash_radius` take `splash_share` of it.
@export_range(0,1000,1) var damage := 60
@export_range(0,20,0.1) var splash_radius := 3.0
@export_range(0,1,0.05) var splash_share := 0.5
## Health of a mine, for shooting one that is detected.
@export_range(1,1000,1) var health := 20
