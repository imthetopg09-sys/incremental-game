extends RefCounted
## Recording, clock, spawn schedule and Sconce rules.


func test_recording_interpolates_and_clamps(t) -> void:
	var r := EchoRecording.new()
	r.record_until(0.0, Vector2(0, 0))
	r.record_until(1.0, Vector2(30, 0))  # fills samples 1..30 with the new position
	r.finish(1.0, Vector2(30, 0), true)
	t.check(r.points.size() == 31, "expected 31 samples, got %d" % r.points.size())
	t.check(r.position_at(-5.0) == Vector2(0, 0), "clamps before start")
	t.check(r.position_at(99.0) == Vector2(30, 0), "clamps after end")
	t.check(r.is_active(1.0) and not r.is_active(1.01), "active only until duration")


func test_recording_path_between(t) -> void:
	var r := EchoRecording.new()
	for i in 61:
		r.record_until(i / EchoRecording.RATE, Vector2(i, 0))
	r.finish(2.0, Vector2(60, 0), true)
	var p := r.path_between(0.5, 1.0)
	t.check(p.size() >= 2, "path has points")
	t.check(is_equal_approx(p[0].x, 15.0) and is_equal_approx(p[p.size() - 1].x, 30.0), "path spans 15..30, got %s..%s" % [p[0], p[p.size() - 1]])
	t.check(r.path_between(3.0, 4.0).size() <= 1, "nothing after the end")


func test_recording_round_trip(t) -> void:
	var r := EchoRecording.new()
	r.run_number = 4
	r.burned = 12
	for i in 10:
		r.record_until(i / EchoRecording.RATE, Vector2(i * 3, i * 2))
	r.finish(9 / EchoRecording.RATE, Vector2(27, 18), false)
	r.picks.append({"t": 0.1, "boon": "moths"})
	var braided := EchoRecording.new()
	braided.record_until(0.0, Vector2(5, 5))
	r.chorus.append(braided)
	# Through real JSON text, the way the save file stores it.
	var back := EchoRecording.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	t.check(back.points == r.points and back.run_number == 4 and back.burned == 12 and back.died == false, "round trip keeps data")
	t.check(back.picks.size() == 1 and back.picks[0]["boon"] == "moths", "keeps boon picks")
	t.check(back.chorus.size() == 1 and back.chorus[0].points[0] == Vector2(5, 5), "keeps braided runs")


func test_clock_labels(t) -> void:
	t.check(NightClock.label(0.0) == "12:00 AM", NightClock.label(0.0))
	t.check(NightClock.label(Tuning.HOUR_LENGTH * 1.5) == "1:30 AM", NightClock.label(Tuning.HOUR_LENGTH * 1.5))
	t.check(NightClock.label(Tuning.NIGHT_LENGTH) == "6:00 AM", NightClock.label(Tuning.NIGHT_LENGTH))
	t.check(NightClock.duration_label(83.4) == "1:23", NightClock.duration_label(83.4))


func test_schedule_is_deterministic_and_escalates(t) -> void:
	var arena := Rect2(Vector2.ZERO, Tuning.ARENA_SIZE)
	var a := SpawnSchedule.new(7, arena)
	var b := SpawnSchedule.new(7, arena)
	var spawns_a := []
	var spawns_b := []
	var tt := 0.0
	while tt < Tuning.NIGHT_LENGTH:
		tt += 1.0 / 60.0
		spawns_a.append_array(a.due(tt))
		# Coarser steps must give the same spawns.
		if int(tt * 60.0) % 4 == 0:
			spawns_b.append_array(b.due(tt))
	spawns_b.append_array(b.due(tt))
	t.check(spawns_a.size() == spawns_b.size(), "step size changed spawn count %d vs %d" % [spawns_a.size(), spawns_b.size()])
	t.check(str(spawns_a) == str(spawns_b), "same seed gives same spawns")
	t.check(SpawnSchedule.interval("wisp", 300.0) < SpawnSchedule.interval("wisp", 0.0), "wisps speed up")
	for s in spawns_a:
		t.check(not arena.has_point(s["pos"]), "spawns off screen, got %s" % s["pos"])
		if not arena.grow(Tuning.SPAWN_MARGIN + 1.0).has_point(s["pos"]):
			t.fail("spawn too far out: %s" % s["pos"])
			break


func test_creepers_and_bloats_wait_for_their_hour(t) -> void:
	var sch := SpawnSchedule.new(1, Rect2(Vector2.ZERO, Tuning.ARENA_SIZE))
	var kinds := {}
	for s in sch.due(Tuning.SPAWNS["creeper"]["start"] - 0.01):
		kinds[s["kind"]] = true
	t.check(kinds.has("wisp") and not kinds.has("creeper") and not kinds.has("bloat"), "only wisps before 1 AM: %s" % kinds.keys())


func test_sconces_keep_until_full_then_choose(t) -> void:
	var gs = load("res://scripts/game_state.gd").new()
	var recs: Array[EchoRecording] = []
	for i in Tuning.START_SCONCES + 1:
		var r := EchoRecording.new()
		r.run_number = i + 1
		recs.append(r)
	for i in Tuning.START_SCONCES:
		t.check(gs.try_keep(recs[i]), "keeps run %d" % (i + 1))
	var newest := recs[Tuning.START_SCONCES]
	t.check(not gs.try_keep(newest), "refuses when full")
	gs.let_go_of(recs[0], newest)
	t.check(gs.echoes.size() == Tuning.START_SCONCES and not gs.echoes.has(recs[0]) and gs.echoes.has(newest), "swap works")
	t.check(gs.let_go.has(recs[0]), "the night keeps what you let go")
	var another := EchoRecording.new()
	gs.let_go_of(another, another)
	t.check(not gs.echoes.has(another) and gs.echoes.size() == Tuning.START_SCONCES, "letting go of the new run keeps the old ones")
	gs.free()
