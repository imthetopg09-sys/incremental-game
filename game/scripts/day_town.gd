extends Control
## The Day Town: the one daylight screen, painted like a watercolor. The first
## Dawn leads here. In this version every building is still asleep; hovering one
## says what it will do once Daylight wakes it.
##
## Assumes GameState.run_number is already the coming night. Dev flag (after `--`):
## --demo-dawn fakes a first Dawn for screenshots.

const INK := Color(0.30, 0.20, 0.14)
const INK_SOFT := Color(0.30, 0.20, 0.14, 0.7)
const GOLD := Color(0.72, 0.44, 0.16)
const GROUND_Y := 548.0
const SUN_POS := Vector2(1010.0, 360.0)
const LAMP_TREE_SCENE := "res://scenes/lamp_tree.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"
## Each building: its name, what it will do, where it stands, its wash color, and
## its outline as points above the ground (y up is negative).
const BUILDINGS: Array[Dictionary] = [
	{
		"name": "Watch Post",
		"hint": "Sends a lamplighter of its own to hold one corner of the square.",
		"x": 190.0,
		"color": Color(0.42, 0.52, 0.64),
		"shape": [Vector2(-30, 0), Vector2(30, 0), Vector2(24, -196), Vector2(36, -200), Vector2(0, -252), Vector2(-36, -200), Vector2(-24, -196)],
		"windows": [Rect2(-10, -186, 20, 24), Rect2(-8, -120, 16, 18), Rect2(-8, -70, 16, 18)],
	},
	{
		"name": "Archive",
		"hint": "Keeps one to three of your Echoes safe through Dawn.",
		"x": 415.0,
		"color": Color(0.72, 0.50, 0.48),
		"shape": [],
		"windows": [Rect2(-84, -96, 22, 60), Rect2(-40, -96, 22, 60), Rect2(18, -96, 22, 60), Rect2(62, -96, 22, 60)],
	},
	{
		"name": "Chandlery",
		"hint": "Candle-makers who spend your Tallow on the Lamp Tree for you.",
		"x": 640.0,
		"color": Color(0.80, 0.62, 0.38),
		"shape": [Vector2(-82, 0), Vector2(82, 0), Vector2(82, -108), Vector2(62, -122), Vector2(62, -168), Vector2(40, -168), Vector2(40, -138), Vector2(0, -172), Vector2(-82, -108)],
		"windows": [Rect2(-56, -84, 26, 26), Rect2(30, -84, 26, 26), Rect2(-13, -60, 26, 60)],
	},
	{
		"name": "Bell Tower",
		"hint": "Rings in the Vigil: your Echoes keep watch longer while you are away.",
		"x": 862.0,
		"color": Color(0.50, 0.62, 0.50),
		"shape": [Vector2(-40, 0), Vector2(40, 0), Vector2(40, -226), Vector2(50, -230), Vector2(0, -318), Vector2(-50, -230), Vector2(-40, -226)],
		"windows": [Rect2(-16, -206, 32, 40), Rect2(-9, -120, 18, 24), Rect2(-9, -64, 18, 24)],
	},
	{
		"name": "The Loom",
		"hint": "Weaves your Echoes into routes you never walked.",
		"x": 1085.0,
		"color": Color(0.60, 0.50, 0.68),
		"shape": [Vector2(-122, 0), Vector2(122, 0), Vector2(122, -98), Vector2(82, -138), Vector2(82, -98), Vector2(41, -138), Vector2(41, -98), Vector2(0, -138), Vector2(0, -98), Vector2(-41, -138), Vector2(-41, -98), Vector2(-82, -138), Vector2(-82, -98), Vector2(-122, -138)],
		"windows": [Rect2(-100, -70, 30, 24), Rect2(-50, -70, 30, 24), Rect2(20, -70, 30, 24), Rect2(70, -70, 30, 24)],
	},
]

@onready var paper: ColorRect = $Paper
@onready var town: Control = $Town
@onready var title_label: Label = %Title
@onready var sub_label: Label = %Sub
@onready var daylight_label: Label = %Daylight
@onready var hint_label: Label = %Hint
@onready var back_button: Button = %Back

## Index into BUILDINGS under the mouse, or -1.
var hovered := -1
var _rects: Array[Rect2] = []
var _washes: Array[Array] = []  # per building: three jittered copies of its outline
var _leaving := false
var _time := 0.0
var _hover_time := 0.0
var input_delay := 0.35
var _opened_at := 0.0


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--demo-dawn") and GameState.dawns == 0:
		GameState.autosave = false
		GameState.night_seconds = 31.0 * 60.0
		GameState.total_burned = 2431
		GameState.run_number = 8
		GameState.greet_dawn(EchoRecording.new())
		GameState.first_dawn_run = 7
		GameState.run_number = 8
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_opened_at = Time.get_ticks_msec() / 1000.0
	(paper.material as ShaderMaterial).set_shader_parameter("sun_pos", SUN_POS)
	_paint()
	town.draw.connect(_draw_town)
	town.gui_input.connect(_on_town_input)
	town.mouse_exited.connect(func(): _hover(-1))
	back_button.pressed.connect(back_to_night)
	_fill_text()
	_hover(-1)


func _fill_text() -> void:
	var minutes := int(round(GameState.first_dawn_seconds / 60.0))
	if GameState.dawns <= 1:
		title_label.text = "First Dawn"
		sub_label.text = "Run %d.   %d minutes of night.   %s shadows burned." % [
			GameState.first_dawn_run, minutes, _thousands(GameState.total_burned)]
	else:
		title_label.text = "The Day Town"
		sub_label.text = "%d Dawns so far. The first came on Run %d, after %d minutes of night." % [
			GameState.dawns, GameState.first_dawn_run, minutes]
	daylight_label.text = "You have %d Daylight. The town is still asleep; Daylight wakes it in the next part of the game." % GameState.daylight


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## Builds each building's outline and three slightly offset copies of it: layered
## translucent washes are what make it read as watercolor.
func _paint() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for b in BUILDINGS:
		var pts := PackedVector2Array()
		var shape: Array = b["shape"]
		if shape.is_empty():
			pts = _archive_shape()
		else:
			for v in shape:
				pts.append(v)
		var base := Vector2(b["x"], GROUND_Y)
		var placed := PackedVector2Array()
		for v in pts:
			placed.append(base + v)
		_rects.append(_bounds(placed).grow(10.0))
		var washes: Array = []
		for layer in 3:
			var jit := PackedVector2Array()
			for v in placed:
				jit.append(v + Vector2(rng.randf_range(-3.5, 3.5), rng.randf_range(-3.5, 3.5)))
			washes.append(jit)
		washes.append(placed)
		_washes.append(washes)


## A columned hall under a dome.
func _archive_shape() -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-112, 0), Vector2(112, 0), Vector2(112, -118), Vector2(70, -118)])
	for i in range(1, 16):
		var a := PI * float(i) / 16.0
		pts.append(Vector2(cos(a) * 70.0, -118.0 - sin(a) * 66.0))
	pts.append_array([Vector2(-70, -118), Vector2(-112, -118)])
	return pts


func _bounds(pts: PackedVector2Array) -> Rect2:
	var r := Rect2(pts[0], Vector2.ZERO)
	for v in pts:
		r = r.expand(v)
	return r


func _process(delta: float) -> void:
	_time += delta
	_hover_time += delta
	town.queue_redraw()


func _draw_town() -> void:
	# The sun behind the rooftops, and a wash of ground.
	for i in 6:
		town.draw_circle(SUN_POS, 46.0 + i * 22.0, Color(1.0, 0.86, 0.55, 0.10))
	town.draw_circle(SUN_POS, 40.0, Color(1.0, 0.93, 0.70, 0.9))
	for k in 3:
		var y := GROUND_Y - 4.0 + k * 3.0
		town.draw_colored_polygon(PackedVector2Array([
			Vector2(0, y + 10), Vector2(320, y - 2), Vector2(700, y + 6), Vector2(1280, y - 6),
			Vector2(1280, 720), Vector2(0, 720)]), Color(0.66, 0.60, 0.42, 0.14))
	_draw_birds()
	for i in BUILDINGS.size():
		_draw_building(i)
	_draw_lamplighter(Vector2(262.0, GROUND_Y))


## You, home from the night, with the lantern still lit.
func _draw_lamplighter(at: Vector2) -> void:
	var ink := Color(INK, 0.75)
	town.draw_colored_polygon(PackedVector2Array([at + Vector2(-9, 0), at + Vector2(9, 0), at + Vector2(4, -30), at + Vector2(-4, -30)]), ink)
	town.draw_circle(at + Vector2(0, -36), 6.0, ink)
	town.draw_line(at + Vector2(3, -24), at + Vector2(15, -16), ink, 2.0, true)
	var glow := 0.5 + 0.1 * sin(_time * 3.0)
	town.draw_circle(at + Vector2(16, -9), 12.0, Color(1.0, 0.7, 0.3, 0.18 * glow))
	town.draw_circle(at + Vector2(16, -9), 4.0, Color(1.0, 0.72, 0.36, 0.95))


func _draw_building(i: int) -> void:
	var b: Dictionary = BUILDINGS[i]
	var awake := i == hovered
	var color: Color = b["color"]
	# Asleep: a paler, greyer wash. Hovered: the color it will have when it wakes.
	var wash := color if awake else color.lerp(Color(0.62, 0.60, 0.60), 0.45).lightened(0.12)
	var lift := Vector2(0, -3.0 * sin(clampf(_hover_time * 6.0, 0.0, PI * 0.5))) if awake else Vector2.ZERO
	var washes: Array = _washes[i]
	for k in 3:
		var pts: PackedVector2Array = washes[k]
		town.draw_colored_polygon(_shift(pts, lift), Color(wash, 0.26))
	# The side away from the sun sits in a darker glaze.
	var half := Rect2(b["x"] - 200.0, 0.0, 200.0 - 6.0, GROUND_Y + 1.0)
	var side := PackedVector2Array([half.position, Vector2(half.end.x, half.position.y), half.end, Vector2(half.position.x, half.end.y)])
	for piece in Geometry2D.intersect_polygons(_shift(washes[1], lift), side):
		town.draw_colored_polygon(piece, Color(wash.darkened(0.3), 0.16))
	# Pigment gathers at the edge of a wash.
	var outline: PackedVector2Array = _shift(washes[3], lift)
	outline.append(outline[0])
	town.draw_polyline(outline, Color(wash.darkened(0.35), 0.45), 1.6, true)
	var base := Vector2(b["x"], GROUND_Y) + lift
	for w in b["windows"]:
		var r: Rect2 = w
		r.position += base
		# Asleep, the shutters are closed; hovered, a warm light shows what is to come.
		town.draw_rect(r, Color(1.0, 0.86, 0.5, 0.75) if awake else Color(wash.darkened(0.5), 0.35))
	var font := get_theme_default_font()
	var name: String = b["name"]
	var size := 17
	var w := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	town.draw_string(font, Vector2(b["x"] - w * 0.5, GROUND_Y + 34.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK if awake else INK_SOFT)
	var tag := "asleep"
	var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	town.draw_string(font, Vector2(b["x"] - tw * 0.5, GROUND_Y + 54.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(INK, 0.4))


func _shift(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	if by == Vector2.ZERO:
		return pts
	var out := PackedVector2Array()
	for v in pts:
		out.append(v + by)
	return out


## A few birds drifting over the rooftops.
func _draw_birds() -> void:
	for i in 4:
		var x := fmod(300.0 + i * 170.0 + _time * (14.0 + i * 3.0), 1400.0) - 60.0
		var y := 230.0 + 26.0 * sin(i * 1.7) + 6.0 * sin(_time * 0.9 + i)
		var flap := 4.0 + 3.0 * sin(_time * 5.0 + i * 2.0)
		var c := Color(INK, 0.45)
		town.draw_polyline(PackedVector2Array([Vector2(x - 9, y - flap), Vector2(x, y), Vector2(x + 9, y - flap)]), c, 1.6, true)


func _on_town_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p: Vector2 = event.position
		var found := -1
		for i in _rects.size():
			if _rects[i].has_point(p):
				found = i
		if found != hovered:
			_hover(found)


func _hover(i: int) -> void:
	hovered = i
	if i < 0:
		hint_label.text = "Hover over a building to see what it will do."
		hint_label.modulate.a = 0.65
	else:
		var b: Dictionary = BUILDINGS[i]
		hint_label.text = "%s:  %s" % [b["name"], b["hint"]]
		hint_label.modulate.a = 1.0
	_hover_time = 0.0


func back_to_night() -> void:
	# Ignore the rest of the double click that left the night's end screen.
	if _leaving or Time.get_ticks_msec() / 1000.0 - _opened_at < input_delay:
		return
	_leaving = true
	Sfx.ui_click()
	GameState.save()
	get_tree().change_scene_to_file(LAMP_TREE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed("ui_cancel"):
		_leaving = true
		GameState.save()
		get_tree().change_scene_to_file(TITLE_SCENE)
	elif event.is_action_pressed("ui_accept"):
		back_to_night()
