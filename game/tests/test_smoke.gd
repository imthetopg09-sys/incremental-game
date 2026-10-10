extends RefCounted
## Boots the main scene and lets it run a few frames.


func test_main_scene_boots(t) -> void:
	var path: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed := load(path) as PackedScene
	t.check(packed != null, "main scene %s failed to load" % path)
	if packed == null:
		return
	var main := packed.instantiate()
	t.root.add_child(main)
	for i in 10:
		await t.process_frame
	var version: Label = main.get_node("Version")
	t.check(version.text == "v" + ProjectSettings.get_setting("application/config/version"), "version label is %s" % version.text)
	main.queue_free()
	await t.process_frame


func test_version_is_semver(t) -> void:
	var v: String = ProjectSettings.get_setting("application/config/version")
	var re := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+$")
	t.check(re.search(v) != null, "version %s is not MAJOR.MINOR.PATCH" % v)
