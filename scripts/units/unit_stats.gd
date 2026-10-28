class_name UnitStats
extends Resource
## Shared design data. Negative combat values mean unresolved, never zero damage.
@export var unit_id: StringName
@export var display_name: String
@export_range(1, 100000, 1) var max_health: int = 1
@export_range(0, 1000, 0.1) var movement_speed: float = 0.0
@export_range(0, 1000, 0.1) var vision: float = 0.0
## -1 means unspecified (Drone).
@export var attack_range: float = -1.0
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
@export_range(0, 100000, 1) var energy_cost: int = 0
@export_range(0, 100000, 1) var iron_cost: int = 0
## Identifiers only; no ability behavior is inferred from this list.
@export var abilities: Array[StringName] = []
@export var mobility: MobilityRules

func has_resolved_attack() -> bool:
	return attack_range >= 0.0 and damage >= 0 and attack_interval > 0.0

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if unit_id == &"": errors.append("Unit ID is required")
	if max_health <= 0 or movement_speed < 0 or vision < 0: errors.append("Invalid health, movement or vision")
	if energy_cost < 0 or iron_cost < 0: errors.append("Costs cannot be negative")
	if attack_range < 0 and attack_range != -1: errors.append("Unknown range must be -1")
	if damage < 0 and damage != -1: errors.append("Unknown damage must be -1")
	if attack_interval <= 0 and attack_interval != -1: errors.append("Interval must be positive or -1")
	if (damage == -1) != (attack_interval == -1): errors.append("Resolve damage and interval together")
	if splash_radius < 0: errors.append("Splash radius cannot be negative")
	if (heavy_target_damage == -1) != (heavy_target_interval == -1): errors.append("Resolve heavy damage and interval together")
	if heavy_target_damage < -1 or (heavy_target_interval <= 0 and heavy_target_interval != -1): errors.append("Invalid heavy attack")
	if mobility != null and mobility.clears_forest and mobility.layer != MobilityRules.Layer.FOREST: errors.append("Forest clearing requires forest mobility")
	return errors
