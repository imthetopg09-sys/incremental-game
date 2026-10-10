extends RefCounted
## SaveGame round trips, bad and missing files, and the title's Start over.

const PATH := "user://test_save_roundtrip.json"
const TITLE_PATH := "user://test_save_title.json"


func _new_state() -> Node:
	return load("res://scripts/game_state.gd").new()


func _rec(run: int, samples: int) -> EchoRecording:
	var r := EchoRecording.new()
	r.run_number = run
	r.burned = run * 2
	for i in samples:
		r.record_until(i / EchoRecording.RATE, Vector2(100 + i * 3, 200 + run))
	r.finish((samples - 1) / EchoRecording.RATE, Vector2(100 + (samples - 1) * 3, 200 + run), true)
	return r


func _cleanup(path: String) -> void:
	for p in [path, path + ".tmp", path + ".bad"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_round_trip_keeps_everything(t) -> void:
	_cleanup(PATH)
	var gs = _new_state()
	gs.run_number = 7
	gs.tallow = 123
	gs.total_burned = 456
	gs.best_time = 201.5
	gs.tree_levels = {"thick_wick": 2, "extra_sconce": 1}
	var a := _rec(3, 40)
	a.hue_index = 0
	a.picks.append({"t": 0.5, "boon": "moths"})
	var braided := _rec(2, 20)
	braided.picks.append({"t": 0.25, "boon": "flare"})
	a.chorus.append(braided)
	var c := _rec(5, 30)
	c.hue_index = 1
	c.died = false
	gs.echoes.append(a)
	gs.echoes.append(c)
	for i in 35:
		gs.let_go.append(_rec(100 + i, 3))
	gs.let_go_count = 35

	t.check(SaveGame.save(gs, PATH), "save returns true")
	t.check(SaveGame.exists(PATH), "save file exists")
	t.check(not FileAccess.file_exists(PATH + ".tmp"), "temp file was renamed away")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	t.check(raw is Dictionary and int(raw.get("version", 0)) == 1, "file carries version 1")

	var back = _new_state()
	back.tallow = 999
	t.check(SaveGame.load_into(back, PATH), "load returns true")
	t.check(back.run_number == 7 and back.tallow == 123 and back.total_burned == 456, "counters: run %d, tallow %d, burned %d" % [back.run_number, back.tallow, back.total_burned])
	t.check(is_equal_approx(back.best_time, 201.5), "best time %s" % back.best_time)
	t.check(back.level("thick_wick") == 2 and back.level("extra_sconce") == 1 and back.level("foresight") == 0, "tree levels %s" % back.tree_levels)
	t.check(back.sconces == gs.sconces, "sconces follow the tree")
	t.check(back.echoes.size() == 2, "two Echoes, got %d" % back.echoes.size())
	if back.echoes.size() == 2:
		var a2: EchoRecording = back.echoes[0]
		var c2: EchoRecording = back.echoes[1]
		t.check(a2.run_number == 3 and a2.points == a.points and a2.hue_index == 0 and a2.burned == 6, "first Echo intact")
		t.check(is_equal_approx(a2.duration, a.duration), "duration %s vs %s" % [a2.duration, a.duration])
		t.check(a2.picks.size() == 1 and a2.picks[0]["boon"] == "moths", "first Echo picks")
		t.check(a2.chorus.size() == 1 and a2.chorus[0].run_number == 2 and a2.chorus[0].points == braided.points, "Chorus member intact")
		t.check(a2.chorus.size() == 1 and a2.chorus[0].picks.size() == 1 and a2.chorus[0].picks[0]["boon"] == "flare", "Chorus member picks")
		t.check(c2.run_number == 5 and c2.hue_index == 1 and not c2.died, "second Echo intact")
	t.check(back.all_recordings().size() == 3, "three runs walk tonight")
	t.check(back.let_go.size() == SaveGame.LET_GO_KEPT, "let go capped at 30, got %d" % back.let_go.size())
	t.check(back.let_go_count == 35, "let go count %d" % back.let_go_count)
	if back.let_go.size() == SaveGame.LET_GO_KEPT:
		t.check(back.let_go[0].run_number == 105 and back.let_go[29].run_number == 134, "keeps the most recent 30")

	# Saving again replaces the file in place.
	back.tallow = 5
	t.check(SaveGame.save(back, PATH), "second save returns true")
	var again = _new_state()
	SaveGame.load_into(again, PATH)
	t.check(again.tallow == 5 and again.let_go.size() == 30 and again.let_go_count == 35, "second save replaced the first")

	SaveGame.erase(PATH)
	t.check(not SaveGame.exists(PATH), "erase removes the file")
	_cleanup(PATH)
	for n in [gs, back, again]:
		n.free()


func test_corrupt_file_is_moved_aside(t) -> void:
	for text in ["{\"version\": 1, \"tallow\": 4", "[1, 2, 3]", ""]:
		_cleanup(PATH)
		_write(PATH, text)
		var gs = _new_state()
		gs.tallow = 50
		gs.run_number = 9
		t.check(not SaveGame.load_into(gs, PATH), "corrupt %s returns false" % JSON.stringify(text))
		t.check(gs.tallow == 0 and gs.run_number == 1 and gs.echoes.is_empty(), "state reset after %s" % JSON.stringify(text))
		t.check(not SaveGame.exists(PATH), "corrupt file no longer at the save path")
		t.check(FileAccess.file_exists(PATH + ".bad"), "corrupt file kept as .bad")
		gs.free()
	_cleanup(PATH)


func test_odd_fields_are_tolerated(t) -> void:
	_cleanup(PATH)
	var good := _rec(4, 10).to_dict()
	_write(PATH, JSON.stringify({
		"version": 1,
		"from_the_future": {"x": 1},
		"run_number": 3,
		"tallow": "lots",
		"echoes": [5, {"picks": "nope"}, {"chorus": [[1]]}, {"died": "maybe"}, good],
		"let_go": "none",
		"tree_levels": {"thick_wick": [1], "wide_glow": 2},
	}))
	var gs = _new_state()
	t.check(SaveGame.load_into(gs, PATH), "a parseable file with odd fields still loads")
	t.check(gs.run_number == 3 and gs.tallow == 0 and gs.best_time == 0.0, "bad or missing numbers fall back")
	t.check(gs.echoes.size() == 1 and gs.echoes[0].run_number == 4, "only the well-formed Echo is kept")
	t.check(gs.let_go.is_empty() and gs.let_go_count == 0, "bad let go list ignored")
	t.check(gs.level("wide_glow") == 2 and gs.level("thick_wick") == 0, "bad tree level ignored, good one kept")
	t.check(not FileAccess.file_exists(PATH + ".bad"), "not treated as corrupt")
	gs.free()
	_cleanup(PATH)


func test_missing_file_returns_false(t) -> void:
	_cleanup(PATH)
	var gs = _new_state()
	gs.tallow = 10
	gs.tree_levels = {"thick_wick": 1}
	t.check(not SaveGame.exists(PATH), "no save yet")
	t.check(not SaveGame.load_into(gs, PATH), "missing file returns false")
	t.check(gs.tallow == 0 and gs.tree_levels.is_empty(), "state reset")
	t.check(not FileAccess.file_exists(PATH + ".bad"), "nothing moved aside")
	gs.free()


func _click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev


func test_title_continue_and_start_over(t) -> void:
	var gs = t.root.get_node_or_null("GameState")
	t.check(gs != null, "GameState autoload is present")
	if gs == null:
		return
	_cleanup(TITLE_PATH)
	gs.reset()
	gs.run_number = 4
	SaveGame.save(gs, TITLE_PATH)
	var main = load("res://scenes/main.tscn").instantiate()
	main.save_path = TITLE_PATH
	t.root.add_child(main)
	await t.process_frame
	var hint: Label = main.get_node("Hint")
	var start_over: Label = main.get_node("StartOver")
	t.check(hint.text.begins_with("Click to tend the Lamp Tree (Run 4 next)"), "hint reads %s" % hint.text)
	t.check(start_over.visible and start_over.text == "Start over", "Start over is offered")
	t.check(start_over.mouse_filter == Control.MOUSE_FILTER_STOP, "Start over catches its own clicks")

	start_over.gui_input.emit(_click())
	t.check(start_over.text == "Click again to erase your save", "first click asks again, got %s" % start_over.text)
	t.check(SaveGame.exists(TITLE_PATH) and not main._starting, "first click neither erases nor starts the night")
	main._process(3.1)
	t.check(start_over.text == "Start over", "the ask expires after 3 s")

	start_over.gui_input.emit(_click())
	main._gui_input(_click())
	t.check(start_over.text == "Start over" and not main._starting, "a click elsewhere backs out without starting")

	start_over.gui_input.emit(_click())
	start_over.gui_input.emit(_click())
	t.check(not SaveGame.exists(TITLE_PATH), "second click erases the save")
	t.check(gs.run_number == 1, "GameState was reset")
	t.check(hint.text.begins_with("Click to strike a match."), "hint reads %s" % hint.text)
	t.check(not start_over.visible and not main._starting, "Start over hides and the night does not start")

	main.queue_free()
	await t.process_frame
	gs.reset()
	_cleanup(TITLE_PATH)
