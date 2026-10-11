class_name Bot
extends RefCounted
## Simple autopilots for balance testing and demo footage.
## "still": never moves. "flee": runs from nearby shadows. "kite": flees, but also
## drags shadows toward where its Echoes are about to walk. "shield": stands on the
## Echo that walks longest (an exploit check: it should not be safe).

## The kite bot waits this far past an Echo's foreseen spot, outside the Echo's
## light, so the shadows chasing it walk through that light.
const KITE_LEAD := 170.0
## Heading smoothing per 1/60 s; scaled by the real step so 30 Hz and 60 Hz agree.
const TURN_RATE := 0.12

var style: String
var _dir := Vector2.ZERO
var _last_t := 0.0
## A per-run habit, so a bot does not replay its last run move for move (a person
## never does, and an exact replay would hide inside its own Echo).
var _habit := 0.0


func _init(style_name := "kite", run_number := 1) -> void:
	style = style_name
	_habit = fmod(run_number * 2.39996, TAU)


func steer(sim: NightSim) -> Vector2:
	var p := sim.player_pos
	var dt := maxf(sim.t - _last_t, 0.0)
	_last_t = sim.t
	if style == "still":
		return p
	if style == "shield":
		var longest := -1
		for i in sim.active_echoes():
			if longest < 0 or sim.echoes[i].duration > sim.echoes[longest].duration:
				longest = i
		if longest >= 0:
			return sim.echoes[longest].position_at(sim.t + dt)
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
			# Wait past the Echo's foreseen spot, outside its light and outside the
			# lantern's outshine, so shadows coming at the lantern cross the Echo.
			var away := p - best
			var spot := best + (away.normalized() if away.length() > 1.0 else Vector2.RIGHT) * KITE_LEAD
			var to_spot := spot - p
			push += to_spot.normalized() * 0.8 * clampf(to_spot.length() / 60.0, 0.0, 1.0)
	push += Vector2.from_angle(sim.t * 0.5 + _habit) * 0.15
	if push.length() < 0.05:
		# Drift in a slow loop so the recording covers ground.
		push = Vector2.from_angle(sim.t * 0.7) * 0.3
	# Smooth the heading like a hand on a mouse would, instead of jittering.
	_dir = _dir.lerp(push.normalized(), 1.0 - pow(1.0 - TURN_RATE, dt * 60.0))
	return p + _dir.normalized() * 120.0


## Picks a Boon from the night's offer: Moths and Chain Spark first.
func pick_boon(sim: NightSim) -> String:
	var choices := sim.offer()
	for id in ["moths", "spark", "candle", "flare"]:
		if choices.has(id):
			return id
	return choices[0] if not choices.is_empty() else ""


## Spends Tallow the way a sensible player might: cheapest useful upgrade first.
static func shop(gs) -> void:
	var order := ["foresight", "thick_wick", "hot_flame", "wide_glow", "extra_sconce", "kindling", "rendering_vat", "afterglow"]
	var bought := true
	while bought:
		bought = false
		var best := ""
		var best_cost := 1 << 30
		for id in order:
			var cost := Upgrades.next_cost(id, gs.level(id))
			if cost >= 0 and cost <= gs.tallow and cost < best_cost:
				best = id
				best_cost = cost
		if best != "":
			gs.buy(best)
			bought = true
