extends SceneTree
## Minimal headless test runner, no addons needed.
## Usage: godot --headless --path game -s res://tests/run_tests.gd
## Runs every `test_*` method in every res://tests/test_*.gd file.
## A test fails by calling `fail(msg)` on the runner or by returning false.

var _failures: Array[String] = []
var _current := ""
var _errors: Array[String] = []


## Script and engine errors logged during a test fail that test, even when the
## erroring call just returned null and the test carried on.
class ErrorCatcher extends Logger:
	var sink: Array[String]

	func _init(errors: Array[String]) -> void:
		sink = errors

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		sink.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var passed := 0
	OS.add_logger(ErrorCatcher.new(_errors))
	# Never touch the real save while testing.
	var gs = root.get_node_or_null("GameState")
	if gs != null:
		gs.autosave = false
		gs.reset()
	var dir := DirAccess.open("res://tests")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		if script == null or not script.can_instantiate():
			_current = file
			fail("failed to load (parse error?)")
			print("  FAIL ", file, " (did not load)")
			continue
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			_current = "%s::%s" % [file, name]
			var before := _failures.size()
			_errors.clear()
			var suite = script.new()
			var result = await suite.call(name, self)
			for err in _errors:
				fail("logged error: " + err)
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
