extends SceneTree
## Minimal headless test runner, no addons needed.
## Usage: godot --headless --path game -s res://tests/run_tests.gd
## Runs every `test_*` method in every res://tests/test_*.gd file.
## A test fails by calling `fail(msg)` on the runner or by returning false.

var _failures: Array[String] = []
var _current := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed := 0
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			_current = "%s::%s" % [file, name]
			var before := _failures.size()
			var suite = script.new()
			var result = await suite.call(name, self)
			if result is bool and result == false:
				fail("returned false")
			if suite is Node:
				suite.free()
			if _failures.size() == before:
				passed += 1
				print("  ok   ", _current)
			else:
				print("  FAIL ", _current)
	print("\n%d passed, %d failed" % [passed, _failures.size()])
	for f in _failures:
		printerr("FAILED: ", f)
	quit(1 if _failures.size() > 0 else 0)


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func check(cond: bool, msg: String) -> void:
	if not cond:
		fail(msg)
