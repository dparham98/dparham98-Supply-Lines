class_name RailLine
extends RefCounted
## A sampled track centre line {points, cum, total, start} (docs/MAGLEV_TRACKS.md), built by the
## rail network and followed by trains. `start` is the distance of the train's starting point along
## the line when the network prepended track behind it.
## Position and tangent at `s`, extrapolating straight past either end.
static func point(track: Dictionary, s: float) -> Array:
	var points: PackedVector3Array = track.points
	var cum: PackedFloat32Array = track.cum
	if points.size() == 0: return [Vector3.ZERO,Vector3.FORWARD]
	if points.size() == 1: return [points[0],Vector3.FORWARD]
	var lo := 1
	var hi := points.size()-1
	while lo < hi:
		var mid := (lo+hi)/2
		if cum[mid] < s: lo = mid+1
		else: hi = mid
	var i := clampi(lo,1,points.size()-1)
	var a: Vector3 = points[i-1]
	var b: Vector3 = points[i]
	var seg: float = cum[i]-cum[i-1]
	var t := 0.0 if seg <= 0.0001 else (s-cum[i-1])/seg
	var tangent := (b-a).normalized()
	return [a+(b-a)*t,tangent]
static func total(track: Dictionary) -> float:
	return track.get("total",0.0)
