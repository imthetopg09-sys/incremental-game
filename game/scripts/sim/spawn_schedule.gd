class_name SpawnSchedule
extends RefCounted
## Deterministic spawns: the same seed always produces the same shadows at the same
## times and places, so a night can be learned.

var _rng := RandomNumberGenerator.new()
var _next := {}
var _arena: Rect2


func _init(seed_value: int, arena: Rect2) -> void:
	_rng.seed = seed_value
	_arena = arena
	for kind in Tuning.SPAWNS:
		_next[kind] = Tuning.SPAWNS[kind]["start"]


static func interval(kind: String, t: float) -> float:
	var s: Dictionary = Tuning.SPAWNS[kind]
	var since := maxf(t - s["start"], 0.0)
	return maxf(s["base"] / (1.0 + since / s["ramp"]), s["min"])


## Returns every spawn due by time `t` as [{kind, pos}], earliest first, so the
## result does not depend on how often this is called.
func due(t: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	while true:
		var kind := ""
		for k in _next:
			if _next[k] <= t and (kind == "" or _next[k] < _next[kind] or (_next[k] == _next[kind] and k < kind)):
				kind = k
		if kind == "":
			break
		out.append({"kind": kind, "pos": _edge_point()})
		_next[kind] += interval(kind, _next[kind])
	return out


func _edge_point() -> Vector2:
	var m := Tuning.SPAWN_MARGIN
	var w := _arena.size.x
	var h := _arena.size.y
	var d := _rng.randf() * 2.0 * (w + h)
	var p: Vector2
	if d < w:
		p = Vector2(d, -m)
	elif d < w + h:
		p = Vector2(w + m, d - w)
	elif d < 2.0 * w + h:
		p = Vector2(d - w - h, h + m)
	else:
		p = Vector2(-m, d - 2.0 * w - h)
	return _arena.position + p
