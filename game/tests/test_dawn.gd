extends RefCounted
## The first Dawn: Daylight, the sun taking every Echo, the Day Town, and the Vigil.

const PATH := "user://test_dawn_save.json"


func _new_state() -> Node:
	return load("res://scripts/game_state.gd").new()


func _rec(run: int, burned: int) -> EchoRecording:
	var r := EchoRecording.new()
	r.run_number = run
	r.burned = burned
	for i in 30:
		r.record_until(i / EchoRecording.RATE, Vector2(200 + i * 10, 200 + run * 40))
	r.finish(29 / EchoRecording.RATE, Vector2(490, 200 + run * 40), true)
	return r


func _cleanup(path: String) -> void:
	for p in [path, path + ".tmp", path + ".bad"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func test_dawn_pays_daylight_and_clears_echoes(t) -> void:
	var gs = _new_state()
	gs.autosave = false
	gs.echoes.append(_rec(1, 10))
	gs.echoes.append(_rec(2, 20))
	gs.award({"wisp": 4}, 300.0)
	gs.award({"wisp": 4}, 360.0)
	var dawn := _rec(3, 30)
	dawn.duration = Tuning.NIGHT_LENGTH
	dawn.run_number = 3
	t.check(gs.greet_dawn(dawn), "the first Dawn says so")
	t.check(gs.daylight == 1 and gs.dawns == 1, "one Daylight, one Dawn")
	t.check(gs.echoes.is_empty(), "the sun took every Echo")
	t.check(gs.first_dawn_run == 3, "first Dawn run is %d" % gs.first_dawn_run)
	t.check(is_equal_approx(gs.first_dawn_seconds, 660.0), "first Dawn after %s s of night" % gs.first_dawn_seconds)
	t.check(gs.best_time >= Tuning.NIGHT_LENGTH, "best night reached dawn")
	t.check(not gs.greet_dawn(dawn), "a second Dawn is not the first")
	t.check(gs.daylight == 2 and gs.first_dawn_run == 3, "the first Dawn's record stays")
	gs.free()


func test_dawn_fields_round_trip(t) -> void:
	_cleanup(PATH)
	var gs = _new_state()
	gs.daylight = 2
	gs.dawns = 2
	gs.first_dawn_run = 9
	gs.first_dawn_seconds = 1834.5
	gs.night_seconds = 2400.25
	gs.last_seen = 1700000000.0
	t.check(SaveGame.save(gs, PATH), "saved")
	var back = _new_state()
	t.check(SaveGame.load_into(back, PATH), "loaded")
	t.check(back.daylight == 2 and back.dawns == 2 and back.first_dawn_run == 9, "dawn counts round trip")
	t.check(is_equal_approx(back.first_dawn_seconds, 1834.5) and is_equal_approx(back.night_seconds, 2400.25), "night time round trips")
	t.check(is_equal_approx(back.last_seen, 1700000000.0), "last seen round trips")
	gs.free()
	back.free()
	_cleanup(PATH)


func test_vigil_pays_for_time_away(t) -> void:
	var gs = _new_state()
	gs.autosave = false
	gs.echoes.append(_rec(1, 100))
	gs.echoes.append(_rec(2, 50))
	var now := 1700000000.0
	gs.last_seen = now - 60.0
	t.check(gs.collect_vigil(now) == 0, "a minute away pays nothing")
	gs.last_seen = now - 2.0 * 3600.0
	var expected := int(150 * GameState.VIGIL_RATE * 2.0)
	var paid: int = gs.collect_vigil(now)
	t.check(paid == expected and gs.tallow == expected, "two hours away paid %d (expected %d)" % [paid, expected])
	t.check(gs.last_seen == now, "the stretch away is counted once")
	t.check(gs.collect_vigil(now + 5.0) == 0, "collecting again right away pays nothing")
	gs.last_seen = now - 100.0 * 3600.0
	paid = gs.collect_vigil(now)
	t.check(paid == int(150 * GameState.VIGIL_RATE * GameState.VIGIL_MAX_AWAY / 3600.0), "time away is capped (paid %d)" % paid)
	gs.last_seen = now + 3600.0
	t.check(gs.collect_vigil(now) == 0, "a clock that went backwards pays nothing")
	gs.echoes.clear()
	gs.last_seen = now - 5.0 * 3600.0
	t.check(gs.collect_vigil(now) == 0, "no Echoes, no Vigil")
	gs.free()


func test_night_dawn_runs_the_sunrise_then_waits(t) -> void:
	var gs = t.root.get_node("GameState")
	gs.reset()
	gs.echoes.append(_rec(1, 5))
	gs.run_number = 2
	var night = (load("res://scenes/night.tscn") as PackedScene).instantiate()
	t.root.add_child(night)
	await t.process_frame
	var sim: NightSim = night.sim
	sim.t = Tuning.NIGHT_LENGTH - 0.05
	sim.flame = 1e9
	sim.max_flame = 1e9
	for i in 10:
		await t.physics_frame
	t.check(night.state == night.State.SUNRISE, "dawn starts the sunrise (state %d)" % night.state)
	night._sunrise_time = night.SUNRISE_PALE + night.SUNRISE_SWEEP + night.SUNRISE_HOLD
	# process_frame fires just before nodes process, so wait two.
	await t.process_frame
	await t.process_frame
	t.check(sim.shadows.is_empty(), "the sun burned every shadow")
	await t.create_timer(1.2).timeout
	t.check(night.state == night.State.WAITING, "the dawn screen waits for a click (state %d)" % night.state)
	t.check(gs.daylight == 1 and gs.echoes.is_empty(), "Daylight paid and Echoes gone")
	t.check(night.overlay_title.text == "First Dawn.", "title is %s" % night.overlay_title.text)
	night.free()
	t.root.get_node("Sfx").stop_all()
	gs.reset()
	await t.process_frame


func test_day_town_boots_and_hovers(t) -> void:
	var gs = t.root.get_node("GameState")
	gs.reset()
	gs.greet_dawn(_rec(4, 10))
	var town = (load("res://scenes/day_town.tscn") as PackedScene).instantiate()
	t.root.add_child(town)
	for i in 3:
		await t.process_frame
	t.check(town.title_label.text == "First Dawn", "title is %s" % town.title_label.text)
	t.check(town.daylight_label.text.begins_with("You have 1 Daylight"), "daylight line: %s" % town.daylight_label.text)
	var ev := InputEventMouseMotion.new()
	ev.position = town._rects[1].get_center()
	town._on_town_input(ev)
	t.check(town.hovered == 1, "hovering the Archive")
	t.check(town.hint_label.text.begins_with("Archive"), "hint: %s" % town.hint_label.text)
	town.free()
	gs.reset()
	await t.process_frame
