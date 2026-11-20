extends "res://scripts/production/production_building.gd"
## The Temple of Science (docs/TEMPLE_OF_SCIENCE.md): a research building. It is placed, built, repaired and
## paid for like a Barracks: it pays from the covering Depot that can (payer_for). It makes no units; it
## carries out one research at a time, and a finished research holds for its whole side.
@export var research: Array[ResearchStats] = []
## The research under way, or null.
var researching: ResearchStats
## Seconds of work done on it.
var research_progress := 0.0
## The Depot that paid for it, refunded on Cancel.
var _research_payer: Node3D
func _ready() -> void:
	super._ready()
	if is_queued_for_deletion(): return
	add_to_group("research_buildings")
func research_by_id(id: StringName) -> ResearchStats:
	for entry in research:
		if entry.research_id == id: return entry
	return null
## Whether the side already has it.
func is_done(id: StringName) -> bool:
	return Research.has(self,team,id)
## Why `id` cannot be started here now, or "" when it can.
func research_blocker(id: StringName) -> String:
	var entry := research_by_id(id)
	if entry == null: return "This building does not research that."
	if is_done(id): return "%s is already researched." % entry.display_name
	if researching != null: return "%s is researching %s." % [stats.display_name,researching.display_name]
	var elsewhere := Research.underway(self,team,id)
	if elsewhere != null: return "%s is already being researched at %s." % [entry.display_name,elsewhere.name]
	if not source_friendly(): return "No friendly Depot's range covers %s." % name
	if payer_for(entry.energy_cost,entry.iron_cost) == null: return "No Depot in range has %d E and %d I for %s." % [entry.energy_cost,entry.iron_cost,entry.display_name]
	return ""
func request_research(id: StringName) -> bool:
	var blocker := research_blocker(id)
	if not blocker.is_empty(): game.notify(blocker); return false
	var entry := research_by_id(id)
	var payer := payer_for(entry.energy_cost,entry.iron_cost)
	_set_source(payer)
	if not payer.spend_local(entry.energy_cost,entry.iron_cost): game.notify("%s lacks local resources for research." % payer.name); return false
	researching = entry
	research_progress = 0.0
	_research_payer = payer
	game.notify("%s research started at %s; paid by %s." % [entry.display_name,name,payer.name])
	return true
## Stops the research under way and gives its cost back to the Depot that paid, while that Depot is still yours.
func cancel_research() -> bool:
	if researching == null: return false
	var entry := researching
	researching = null
	research_progress = 0.0
	if _depot_ok(_research_payer):
		_research_payer.stockpile.deposit(&"energy",entry.energy_cost)
		_research_payer.stockpile.deposit(&"iron",entry.iron_cost)
		game.notify("%s research cancelled; %d E and %d I went back to %s." % [entry.display_name,entry.energy_cost,entry.iron_cost,_research_payer.name])
	else: game.notify("%s research cancelled." % entry.display_name)
	_research_payer = null
	return true
func fraction() -> float:
	return clampf(research_progress/researching.seconds,0.0,1.0) if researching != null else 0.0
func seconds_left() -> float:
	return maxf(0.0,researching.seconds-research_progress) if researching != null else 0.0
## A captured paying Depot loses the research it paid for, as a production queue is lost (production_building).
func _source_changed() -> void:
	super._source_changed()
	researching = null
	research_progress = 0.0
	_research_payer = null
func _process(delta: float) -> void:
	if not source_friendly():
		$Status.text = stats.display_name+(" · no Depot in range · research paused" if researching != null else " · no Depot in range")
		_show_model(&"show_research",[false])
		return
	if researching == null:
		$Status.text = "%s → %s" % [stats.display_name,assigned_depot.name]
		_show_model(&"show_research",[false])
		return
	research_progress = minf(researching.seconds,research_progress+delta)
	_show_model(&"show_research",[true])
	if research_progress >= researching.seconds:
		var entry := researching
		researching = null
		research_progress = 0.0
		_research_payer = null
		Research.complete(self,team,entry.research_id)
		game.notify("%s researched at %s." % [entry.display_name,name])
		$Status.text = "%s → %s" % [stats.display_name,assigned_depot.name]
		return
	$Status.text = "%s · %s · %d%%" % [stats.display_name,researching.display_name,roundi(fraction()*100)]
