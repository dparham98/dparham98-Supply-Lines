class_name GeneratorRules
extends Resource
## Editable proposed balance, not original supplied unit values.
@export_range(1,10000) var wood_output := 10
@export_range(0.1,120) var wood_seconds := 2.0
@export_range(1,10000) var coal_output := 50
@export_range(0.1,120) var coal_seconds := 5.0
func output(kind: StringName) -> int: return coal_output if kind == &"coal" else wood_output
func seconds(kind: StringName) -> float: return coal_seconds if kind == &"coal" else wood_seconds
