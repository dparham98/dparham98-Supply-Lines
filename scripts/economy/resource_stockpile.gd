class_name ResourceStockpile
extends RefCounted
const KINDS: Array[StringName] = [&"energy",&"iron",&"wood",&"coal"]
var _capacity: int
var capacity: int:
	get: return _capacity
	set(value):
		if value >= 1 and value >= total(): _capacity = value
var _amounts: Dictionary = {}
## Crate shipments (docs/CRATE_SHIPMENTS.md): whole crates of one resource, oldest first. Crated units
## still count toward storage but are reserved: withdraw and spend never touch them.
const CRATE := 25
var _crates: Array[StringName] = []
## Keep stocked: repack crates up to these counts whenever loose stock allows.
var keep_stocked := false
var stock_targets := {}
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
	_amounts[kind] = clampi(value,crated(kind),space()+amount(kind))
func crate_count(kind: StringName = &"") -> int:
	return _crates.size() if kind.is_empty() else _crates.count(kind)
func crated(kind: StringName) -> int: return crate_count(kind)*CRATE
func crates() -> Array[StringName]: return _crates.duplicate()
## Loose units that can be spent, withdrawn or packed.
func available(kind: StringName) -> int: return amount(kind)-crated(kind)
func pack(kind: StringName) -> bool:
	if not KINDS.has(kind) or available(kind) < CRATE: return false
	_crates.append(kind)
	return true
func unpack(kind: StringName) -> bool:
	var index := _crates.rfind(kind)
	if index < 0: return false
	_crates.remove_at(index)
	return true
## Removes the oldest crate with its units; returns its resource or "" when none.
func take_crate() -> StringName:
	if _crates.is_empty(): return &""
	var kind: StringName = _crates.pop_front()
	_amounts[kind] -= CRATE
	return kind
## Adds a whole crate if it fits.
func put_crate(kind: StringName) -> bool:
	if not KINDS.has(kind) or space() < CRATE: return false
	_amounts[kind] += CRATE
	_crates.append(kind)
	return true
func set_target(kind: StringName, count: int) -> void:
	stock_targets[kind] = maxi(0,count)
func restock() -> void:
	if not keep_stocked: return
	for kind in stock_targets:
		while crate_count(kind) < stock_targets[kind] and pack(kind): pass
func deposit(kind: StringName, requested: int) -> int:
	if not KINDS.has(kind) or requested <= 0: return 0
	var accepted := mini(requested,space())
	_amounts[kind] += accepted
	return accepted
func withdraw(kind: StringName, requested: int) -> int:
	if not KINDS.has(kind) or requested <= 0: return 0
	var taken := mini(requested,available(kind))
	_amounts[kind] -= taken
	return taken
func spend(costs: Dictionary) -> bool:
	for kind in costs:
		if not KINDS.has(kind) or typeof(costs[kind]) != TYPE_INT or costs[kind] < 0 or available(kind) < costs[kind]: return false
	for kind in costs: _amounts[kind] -= costs[kind]
	return true
static func transfer(source: ResourceStockpile, destination: ResourceStockpile, kind: StringName, requested: int) -> int:
	if source == null or destination == null or source == destination or not KINDS.has(kind) or requested <= 0: return 0
	var moved := mini(requested,mini(source.available(kind),destination.space()))
	source.withdraw(kind,moved)
	destination.deposit(kind,moved)
	return moved
