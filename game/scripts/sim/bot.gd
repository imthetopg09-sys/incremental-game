class_name Bot
extends RefCounted
## Simple autopilots for balance testing and demo footage.
## "still": never moves. "flee": runs from nearby shadows. "kite": flees, but also
## drags shadows toward where its Echoes are about to walk.

var style: String
var _dir := Vector2.ZERO


func _init(style_name := "kite") -> void:
	style = style_name


func steer(sim: NightSim) -> Vector2:
	var p := sim.player_pos
	if style == "still":
		return p
	var push := Vector2.ZERO
	for s in sim.shadows:
		var d := p - s.pos
		var len := maxf(d.length(), 1.0)
		if len < 260.0:
			push += d / len * (260.0 - len) / 260.0 * (2.0 if s.kind == "creeper" else 1.0)
	# Keep off the walls, where shadows pin you.
	var c := sim.arena.get_center()
	var to_center := (c - p) / (sim.arena.size * 0.5)
	push += Vector2(to_center.x * absf(to_center.x), to_center.y * absf(to_center.y)) * 2.2
	if style == "kite":
		var best := Vector2.ZERO
		var best_d := INF
		for i in sim.active_echoes():
			var ahead := sim.echoes[i].position_at(sim.t + Tuning.FORESIGHT_SECONDS)
			var d := ahead.distance_to(p)
			if d < best_d:
				best_d = d
				best = ahead
		if best_d < 400.0:
			push += (best - p).normalized() * 0.8
	if push.length() < 0.05:
		# Drift in a slow loop so the recording covers ground.
		push = Vector2.from_angle(sim.t * 0.7) * 0.3
	# Smooth the heading like a hand on a mouse would, instead of jittering.
	_dir = _dir.lerp(push.normalized(), 0.12)
	return p + _dir.normalized() * 120.0
