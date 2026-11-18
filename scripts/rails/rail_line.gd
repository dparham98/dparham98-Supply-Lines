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
## The distance along the line of the centre-line point nearest `at`, from `from` on.
static func nearest(track: Dictionary, at: Vector3, from := -INF) -> float:
	var points: PackedVector3Array = track.points
	var cum: PackedFloat32Array = track.cum
	var best := INF
	var best_s: float = maxf(from,cum[0]) if cum.size() > 0 else 0.0
	for i in range(1,points.size()):
		if cum[i] < from: continue
		var a: Vector3 = points[i-1]
		var b: Vector3 = points[i]
		var ab := b-a
		var t := clampf((at-a).dot(ab)/maxf(ab.length_squared(),0.000001),0.0,1.0)
		var d := (a+ab*t).distance_squared_to(at)
		if d < best:
			best = d
			best_s = maxf(from,cum[i-1]+(cum[i]-cum[i-1])*t)
	return best_s
static func total(track: Dictionary) -> float:
	return track.get("total",0.0)
