extends RefCounted
## Whole-night behavior, run headless at a fixed step.

const DT := 1.0 / 60.0


static func run(sim: NightSim, target_fn: Callable, max_t := Tuning.NIGHT_LENGTH + 1.0) -> void:
	while not sim.is_over() and sim.t < max_t:
		sim.step(DT, target_fn.call(sim))


func test_standing_still_dies_before_dawn(t) -> void:
	var sim := NightSim.new()
	run(sim, func(s): return s.arena.get_center())
	t.check(not sim.alive, "a lantern that never moves should go out")
	t.check(sim.recording.died and is_equal_approx(sim.recording.duration, sim.t), "recording ends at death")
	t.check(sim.burned > 0, "it burned something first")


static func _make_unkillable(sim: NightSim) -> void:
	sim.max_flame = 1e12
	sim.flame = 1e12


func test_unkillable_lantern_reaches_dawn(t) -> void:
	var sim := NightSim.new()
	_make_unkillable(sim)
	run(sim, func(s): return s.arena.get_center())
	t.check(sim.reached_dawn and not sim.recording.died, "reaches 6 AM")
	t.check(absf(sim.recording.duration - Tuning.NIGHT_LENGTH) < 0.05, "duration %.2f" % sim.recording.duration)


func test_echoes_burn_shadows(t) -> void:
	# Record a run that sweeps the square, then replay it as an Echo.
	var sweep := func(s: NightSim) -> Vector2:
		var a: float = s.t * 0.9
		return s.arena.get_center() + Vector2(cos(a) * 420.0, sin(a * 1.3) * 230.0)
	var first := NightSim.new()
	run(first, sweep, 90.0)
	first.recording.finish(first.t, first.player_pos, true)
	var echoes: Array[EchoRecording] = [first.recording]
	var second := NightSim.new(echoes, Tuning.NIGHT_SEED, 2)
	_make_unkillable(second)
	run(second, func(s): return Vector2(60, 60), 90.0)
	t.check(second.burned_by_echoes > 0, "echo burned %d" % second.burned_by_echoes)


func test_bloats_split(t) -> void:
	var sim := NightSim.new()
	_make_unkillable(sim)
	sim._spawn("bloat", sim.player_pos + Vector2(40, 0))
	var split := false
	for i in 600:
		sim.step(DT, sim.player_pos)
		for e in sim.events:
			if e["type"] == "split":
				split = true
		if split:
			break
	var mites := sim.shadows.filter(func(s): return s.kind == "mite").size()
	t.check(split and mites == Tuning.BLOAT_SPLIT, "bloat split into %d mites" % mites)


func test_light_shrinks_with_flame(t) -> void:
	var sim := NightSim.new()
	var full := sim.light_radius()
	sim.flame = 0.0
	t.check(sim.light_radius() < full and sim.light_radius() > 0.0, "light shrinks but never vanishes")
