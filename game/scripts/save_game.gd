class_name SaveGame
extends RefCounted
## Writes GameState to a JSON file and reads it back. Writes are atomic (a temp
## file renamed over the real one), and a file that will not parse is moved
## aside to `<path>.bad` instead of crashing the game.

const PATH := "user://save.json"
const VERSION := 1
## Let-go Echoes are only kept for flavor; the count survives in full.
const LET_GO_KEPT := 30


static func save(gs: Node, path := PATH) -> bool:
	var let_go: Array = gs.let_go.slice(maxi(0, gs.let_go.size() - LET_GO_KEPT))
	var data := {
		"version": VERSION,
		"run_number": gs.run_number,
		"echoes": gs.echoes.map(func(e): return e.to_dict()),
		# Let-go Echoes never walk again; their numbers are all that is kept.
		"let_go": let_go.map(func(e): return {"run": e.run_number, "duration": e.duration, "died": e.died, "burned": e.burned}),
		"let_go_count": gs.let_go_count,
		"best_time": gs.best_time,
		"tallow": gs.tallow,
		"total_burned": gs.total_burned,
		"tree_levels": gs.tree_levels.duplicate(),
		"daylight": gs.daylight,
		"dawns": gs.dawns,
		"first_dawn_run": gs.first_dawn_run,
		"first_dawn_seconds": gs.first_dawn_seconds,
		"night_seconds": gs.night_seconds,
		"last_seen": gs.last_seen,
	}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return false
	# Full precision, so pick times and durations come back bit for bit.
	var wrote := f.store_string(JSON.stringify(data, "", true, true))
	f.close()
	if not wrote:
		DirAccess.remove_absolute(tmp)
		return false
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("SaveGame: cannot replace %s (%s)" % [path, error_string(err)])
		return false
	return true


## Resets `gs`, then fills it from the file. Returns false (leaving `gs` reset)
## when there is no file or it is unreadable; an unparseable file becomes `.bad`.
static func load_into(gs: Node, path := PATH) -> bool:
	gs.reset()
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty() and FileAccess.get_open_error() != OK:
		push_warning("SaveGame: cannot read %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_warning("SaveGame: %s is corrupt, moving it to %s.bad" % [path, path])
		DirAccess.rename_absolute(path, path + ".bad")
		return false
	var d: Dictionary = json.data
	gs.run_number = maxi(1, _int(d, "run_number", 1))
	gs.best_time = maxf(0.0, _float(d, "best_time", 0.0))
	gs.tallow = maxi(0, _int(d, "tallow", 0))
	gs.total_burned = maxi(0, _int(d, "total_burned", 0))
	gs.daylight = maxi(0, _int(d, "daylight", 0))
	gs.dawns = maxi(0, _int(d, "dawns", 0))
	gs.first_dawn_run = maxi(0, _int(d, "first_dawn_run", 0))
	gs.first_dawn_seconds = maxf(0.0, _float(d, "first_dawn_seconds", 0.0))
	gs.night_seconds = maxf(0.0, _float(d, "night_seconds", 0.0))
	gs.last_seen = maxf(0.0, _float(d, "last_seen", 0.0))
	for e in _echoes(d.get("echoes")):
		gs.echoes.append(e)
	for e in _echoes(d.get("let_go")):
		gs.let_go.append(e)
	gs.let_go_count = maxi(gs.let_go.size(), _int(d, "let_go_count", 0))
	var levels = d.get("tree_levels")
	if levels is Dictionary:
		for id in levels:
			if (levels[id] is float or levels[id] is int) and not Upgrades.node(str(id)).is_empty():
				gs.tree_levels[str(id)] = clampi(int(levels[id]), 0, Upgrades.max_level(str(id)))
	return true


static func exists(path := PATH) -> bool:
	return FileAccess.file_exists(path)


static func erase(path := PATH) -> void:
	for p in [path, path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


static func _int(d: Dictionary, key: String, fallback: int) -> int:
	var v = d.get(key)
	return int(v) if v is float or v is int else fallback


static func _float(d: Dictionary, key: String, fallback: float) -> float:
	var v = d.get(key)
	return float(v) if v is float or v is int else fallback


## Recordings from a JSON array, skipping any entry with the wrong shape.
static func _echoes(list) -> Array[EchoRecording]:
	var out: Array[EchoRecording] = []
	if list is Array:
		for item in list:
			if _is_echo_dict(item):
				out.append(EchoRecording.from_dict(item))
	return out


## True when EchoRecording.from_dict can read `d` without hitting a bad type.
static func _is_echo_dict(d) -> bool:
	if not d is Dictionary:
		return false
	for key in ["duration", "died", "run", "burned", "hue"]:
		if d.has(key) and not (d[key] is float or d[key] is int or d[key] is bool):
			return false
	var picks = d.get("picks", [])
	if not picks is Array or not picks.all(func(p): return p is Dictionary and (p.get("t", 0.0) is float or p.get("t", 0.0) is int)):
		return false
	var chorus = d.get("chorus", [])
	return chorus is Array and chorus.all(func(c): return _is_echo_dict(c))
