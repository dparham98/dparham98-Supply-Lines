class_name ResourceStockpile
extends RefCounted
const KINDS: Array[StringName] = [&"energy",&"iron",&"wood",&"coal"]
var _capacity: int
var capacity: int:
	get: return _capacity
	set(value):
		if value >= 1 and value >= total(): _capacity = value
var _amounts: Dictionary = {}
func _init(limit: int = 2000) -> void:
	capacity = maxi(1,limit)
	for kind in KINDS: _amounts[kind] = 0
func amount(kind: StringName) -> int: return _amounts.get(kind,0)
func total() -> int:
	var result := 0
	for kind in KINDS: result += amount(kind)
	return result
func space() -> int: return maxi(0,capacity-total())
func resize(limit: int) -> bool:
	if limit < 1 or limit < total(): return false
	capacity = limit
	return true
func set_amount(kind: StringName, value: int) -> void:
	if not KINDS.has(kind): return
	_amounts[kind] = clampi(value,0,space()+amount(kind))
func deposit(kind: StringName, requested: int) -> int:
	if not KINDS.has(kind) or requested <= 0: return 0
	var accepted := mini(requested,space())
	_amounts[kind] += accepted
	return accepted
func withdraw(kind: StringName, requested: int) -> int:
	if not KINDS.has(kind) or requested <= 0: return 0
	var taken := mini(requested,amount(kind))
	_amounts[kind] -= taken
	return taken
func spend(costs: Dictionary) -> bool:
	for kind in costs:
		if not KINDS.has(kind) or typeof(costs[kind]) != TYPE_INT or costs[kind] < 0 or amount(kind) < costs[kind]: return false
	for kind in costs: _amounts[kind] -= costs[kind]
	return true
static func transfer(source: ResourceStockpile, destination: ResourceStockpile, kind: StringName, requested: int) -> int:
	if source == null or destination == null or source == destination or not KINDS.has(kind) or requested <= 0: return 0
	var moved := mini(requested,mini(source.amount(kind),destination.space()))
	source.withdraw(kind,moved)
	destination.deposit(kind,moved)
	return moved
