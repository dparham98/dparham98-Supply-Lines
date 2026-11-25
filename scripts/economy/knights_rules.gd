class_name KnightsRules
extends Resource
## The Knights' economy (docs/KNIGHTS_ECONOMY.md): Farms, Houses and housing. Every number is a play-test
## starting point; edit `assets/economy/knights_rules.tres` and restart.
@export_group("Farm")
@export_range(0,10000) var farm_wood_cost := 30
## A Farm is a flat field: any unit walks over it and nothing is built on it (round 2 of the balance research).
@export var farm_footprint := Vector2i(10,10)
## Food a Forester takes from the Farm each work beat (1.2 s). One Forester only.
@export_range(1,100) var farm_food_per_beat := 2
@export_range(1,100000) var farm_health := 300
## A Forester sent to a Farm becomes its Farmer for good: it works only a Farm, and builds, fells and goes nowhere
## else. When its Farm is lost it may take over an empty Farm and nothing else.
@export var farmers_permanent := true
## A Farm yields nothing while an enemy ground unit stands on its field. Seconds between checks.
@export_range(0.05,5.0,0.05) var farm_raid_check_seconds := 0.25
@export_group("House")
@export_range(0,10000) var house_wood_cost := 40
@export var house_footprint := Vector2i(4,4)
## Housing a House adds while it stands inside a friendly Keep's range.
@export_range(0,100) var house_room := 8
@export_range(1,100000) var house_health := 300
@export_group("Housing")
## Housing each standing Keep gives.
@export_range(0,100) var keep_room := 10
## Housing each unit takes, by unit id; units not listed take none. There is no upper limit on housing.
@export var housing := {&"forester_maiden": 1, &"warhound": 1, &"round_table_marine": 2, &"grail_sentinel": 2, &"questing_marine": 2, &"azure_dragon": 4}
