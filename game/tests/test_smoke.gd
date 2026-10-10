extends RefCounted
## Boots each scene and lets it run a few frames.


func _boot(t, path: String, frames := 10) -> Node:
	var packed := load(path) as PackedScene
	t.check(packed != null, "scene %s failed to load" % path)
	if packed == null:
		return null
	var node := packed.instantiate()
	t.root.add_child(node)
	for i in frames:
		await t.process_frame
	return node


func test_main_scene_boots(t) -> void:
	var main = await _boot(t, ProjectSettings.get_setting("application/run/main_scene"))
	if main == null:
		return
	var version: Label = main.get_node("Version")
	t.check(version.text == "v" + ProjectSettings.get_setting("application/config/version"), "version label is %s" % version.text)
	main.queue_free()
	await t.process_frame


func test_night_scene_runs_and_ends(t) -> void:
	var gs = t.root.get_node_or_null("GameState")
	t.check(gs != null, "GameState autoload is present")
	if gs == null:
		return
	gs.reset()
	var night = await _boot(t, "res://scenes/night.tscn", 30)
	if night == null:
		return
	t.check(night.sim.t > 0.0, "the night is ticking")
	night.sim.flame = 0.0
	for i in 5:
		await t.physics_frame
	t.check(not night.sim.alive, "the lantern went out")
	await t.create_timer(1.3).timeout
	t.check(gs.echoes.size() == 1, "the run was kept as an Echo")
	night.queue_free()
	gs.reset()
	await t.process_frame


func test_version_is_semver(t) -> void:
	var v: String = ProjectSettings.get_setting("application/config/version")
	var re := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	t.check(re.search(v) != null, "version %s is not MAJOR.MINOR.PATCH" % v)
