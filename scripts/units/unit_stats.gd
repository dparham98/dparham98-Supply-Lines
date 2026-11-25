class_name UnitStats
extends Resource
## Shared design data. Negative combat values mean unresolved, never zero damage.
@export var unit_id: StringName
@export var display_name: String
@export_range(1, 100000, 1) var max_health: int = 1
@export_range(0, 1000, 0.1) var movement_speed: float = 0.0
@export_range(0, 1000, 0.1) var vision: float = 0.0
## Degrees a second the body turns while travelling (docs/PATHING.md).
@export_range(1, 3600, 1) var turn_rate: float = 360.0
## -1 means unspecified (Drone).
@export var attack_range: float = -1.0
## The main weapon cannot fire at anything nearer than this; 0 is no minimum (the Tank, docs/BASTION_TANK.md).
@export_range(0, 1000, 0.1) var min_attack_range: float = 0.0
## Set both only after interpreting/confirming the original notation.
@export var damage: int = -1
@export var attack_interval: float = -1.0
@export var combat_notation: String = ""
## Combat abilities. Splash radius is provisional balance, measured in map units.
@export var fire_while_moving := false
@export_range(0, 100, 0.1) var splash_radius: float = 0.0
## -1 uses the base attack. Heavy targets are Tanks and selectable buildings.
@export var heavy_target_damage: int = -1
@export var heavy_target_interval: float = -1.0
## Share of the damage that units caught in the splash take, other than the one aimed at (docs/SEE_TO_SHOOT.md).
@export_range(0, 1, 0.05) var splash_share: float = 1.0
## The arc, centred on the hull's heading, inside which a unit on the move may fire; 360 lets it fire any way.
## Held in reserve against kiting (docs/SEE_TO_SHOOT.md); every unit has it at 360 for now.
@export_range(0, 360, 5) var moving_fire_arc: float = 360.0
@export_range(0, 100000, 1) var energy_cost: int = 0
@export_range(0, 100000, 1) var iron_cost: int = 0
@export_range(0, 100000, 1) var food_cost: int = 0
@export_range(0, 100000, 1) var wood_cost: int = 0
## Seconds a production building takes to print this unit at its base energy cost (1x power;
## docs/PRODUCTION_POWER.md). More power divides it.
@export_range(0.5, 600, 0.5) var build_seconds: float = 10.0
## Identifiers only; no ability behavior is inferred from this list.
@export var abilities: Array[StringName] = []
@export var mobility: MobilityRules
## Detects hidden things (armed mines) within this many metres for its side (Detection, docs/MINES.md). 0 for
## none: only the Drone (20) and the Warhound (10) detect, besides Depots and Keeps at their range.
@export_range(0, 200, 0.5) var detect_range: float = 0.0

func has_resolved_attack() -> bool:
	return attack_range >= 0.0 and damage >= 0 and attack_interval > 0.0

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if unit_id == &"": errors.append("Unit ID is required")
	if max_health <= 0 or movement_speed < 0 or vision < 0: errors.append("Invalid health, movement or vision")
	if energy_cost < 0 or iron_cost < 0 or food_cost < 0 or wood_cost < 0: errors.append("Costs cannot be negative")
	if build_seconds <= 0: errors.append("Build time must be positive")
	if attack_range < 0 and attack_range != -1: errors.append("Unknown range must be -1")
	if damage < 0 and damage != -1: errors.append("Unknown damage must be -1")
	if attack_interval <= 0 and attack_interval != -1: errors.append("Interval must be positive or -1")
	if (damage == -1) != (attack_interval == -1): errors.append("Resolve damage and interval together")
	if splash_radius < 0: errors.append("Splash radius cannot be negative")
	if min_attack_range < 0 or (min_attack_range > 0 and min_attack_range >= attack_range): errors.append("Minimum range must be below the range")
	if (heavy_target_damage == -1) != (heavy_target_interval == -1): errors.append("Resolve heavy damage and interval together")
	if heavy_target_damage < -1 or (heavy_target_interval <= 0 and heavy_target_interval != -1): errors.append("Invalid heavy attack")
	if mobility != null and mobility.clears_forest and mobility.layer != MobilityRules.Layer.FOREST: errors.append("Forest clearing requires forest mobility")
	return errors
