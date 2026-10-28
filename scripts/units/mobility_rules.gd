class_name MobilityRules
extends Resource
enum Layer { GROUND, FOREST, AIR }
@export var layer: Layer = Layer.GROUND
## Tank clears entered forest cells; planning alone never changes terrain.
@export var clears_forest := false
