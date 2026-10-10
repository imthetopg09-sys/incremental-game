extends Control
## Title screen: a lantern follows the mouse over a dark square. Click to begin.
## With a save on disk the click continues it, and "Start over" (two clicks) erases it.

const BASE_RADIUS := 220.0
const STRIKE_RADIUS := 360.0
const LIGHT_FOLLOW := 12.0
const LIGHT_COLOR := Color(1.0, 0.68, 0.32)
const HINT_NEW := "Click to strike a match. Esc quits."
const HINT_CONTINUE := "Click to continue: Run %d. Esc quits."
const HINT_TREE := "Click to tend the Lamp Tree (Run %d next). Esc quits."
const START_OVER := "Start over"
const START_OVER_CONFIRM := "Click again to erase your save"
## How long the second click on "Start over" has to land.
const CONFIRM_WINDOW := 3.0
const START_OVER_IDLE := Color(0.85, 0.78, 0.68, 0.55)
const START_OVER_HOVER := Color(1.0, 0.86, 0.62, 1.0)
const START_OVER_WARN := Color(1.0, 0.58, 0.42, 1.0)

@onready var night: ColorRect = $Night
@onready var lantern: Control = $Lantern
@onready var version_label: Label = $Version
@onready var hint_label: Label = $Hint
@onready var start_over: Label = $StartOver
@onready var subtitle: Label = $Subtitle

## Where the save lives. Tests point this at a scratch file before the title enters the tree.
var save_path := SaveGame.PATH

var _light_pos := Vector2.ZERO
var _radius := BASE_RADIUS
var _starting := false
var _confirm_left := 0.0
var _hovering := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	lantern.draw.connect(_draw_lantern)
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_light_pos = size * 0.5
	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("light_count", 1)
	mat.set_shader_parameter("light_colors", PackedVector4Array([Vector4(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, 1.0)]))
	start_over.gui_input.connect(_on_start_over_input)
	start_over.mouse_entered.connect(_set_hovering.bind(true))
	start_over.mouse_exited.connect(_set_hovering.bind(false))
	_refresh_save_ui()
	_show_vigil()


func _refresh_save_ui() -> void:
	var has_save := SaveGame.exists(save_path)
	if not has_save:
		hint_label.text = HINT_NEW
	elif _between_nights():
		hint_label.text = HINT_TREE % GameState.run_number
	else:
		hint_label.text = HINT_CONTINUE % GameState.run_number
	_progress_label().text = _progress_text() if has_save else ""
	if GameState.daylight > 0:
		subtitle.text = "It is midnight again. You have %d Daylight." % GameState.daylight
	else:
		subtitle.text = "It is midnight. It is always midnight."
	start_over.visible = has_save
	_confirm_left = 0.0
	_style_start_over()


## Once per launch: what the Echoes earned keeping watch while the game was closed.
func _show_vigil() -> void:
	if GameState.vigil_paid <= 0:
		return
	var away := int(GameState.vigil_away / 60.0)
	var label := Label.new()
	label.text = "While you were away, your Echoes kept watch for %s.   +%d Tallow" % [
		"%d h %d m" % [floori(away / 60.0), away % 60] if away >= 60 else "%d m" % away, GameState.vigil_paid]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.45))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -130.0
	label.offset_bottom = -100.0
	add_child(label)
	GameState.vigil_paid = 0


## A saved game past its first night resumes on the Lamp Tree, where Tallow is spent.
func _between_nights() -> bool:
	return GameState.run_number > 1


func _progress_text() -> String:
	var parts: Array[String] = ["Run %d next" % GameState.run_number, "%d Tallow" % GameState.tallow]
	if GameState.best_time >= Tuning.NIGHT_LENGTH:
		parts.append("best night reached dawn")
	elif GameState.best_time > 0.0:
		parts.append("best night %s" % NightClock.label(GameState.best_time))
	if not GameState.echoes.is_empty():
		parts.append("%d %s kept" % [GameState.echoes.size(), "Echo" if GameState.echoes.size() == 1 else "Echoes"])
	return "   ".join(parts)


func _progress_label() -> Label:
	var label := get_node_or_null("Progress") as Label
	if label == null:
		label = Label.new()
		label.name = "Progress"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.68, 0.7))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 6)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		label.offset_top = 246.0
		label.offset_bottom = 272.0
		add_child(label)
	return label


func _style_start_over() -> void:
	start_over.text = START_OVER_CONFIRM if _confirm_left > 0.0 else START_OVER
	var color := START_OVER_WARN if _confirm_left > 0.0 else START_OVER_IDLE
	if _hovering:
		color = color.lerp(START_OVER_HOVER, 0.5) if _confirm_left > 0.0 else START_OVER_HOVER
	start_over.add_theme_color_override("font_color", color)


func _set_hovering(on: bool) -> void:
	_hovering = on
	_style_start_over()


func _on_start_over_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or _starting:
		return
	start_over.accept_event()
	if _confirm_left > 0.0:
		SaveGame.erase(save_path)
		GameState.reset()
		_refresh_save_ui()
	else:
		_confirm_left = CONFIRM_WINDOW
		_style_start_over()


func _process(delta: float) -> void:
	var target := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(target):
		target = size * 0.5
	# Frame-rate independent easing toward the cursor.
	_light_pos = _light_pos.lerp(target, 1.0 - exp(-LIGHT_FOLLOW * delta))
	_radius = lerpf(_radius, BASE_RADIUS, 1.0 - exp(-3.0 * delta))
	if _confirm_left > 0.0:
		_confirm_left -= delta
		if _confirm_left <= 0.0:
			_style_start_over()

	var flicker := 0.94 + 0.04 * sin(Time.get_ticks_msec() * 0.013)
	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("lights", PackedVector4Array([Vector4(_light_pos.x, _light_pos.y, _radius * flicker, 1.0)]))
	mat.set_shader_parameter("rect_size", night.size)
	lantern.queue_redraw()


func _draw_lantern() -> void:
	lantern.draw_circle(_light_pos, 10.0, LIGHT_COLOR)
	lantern.draw_circle(_light_pos, 5.0, Color(1.0, 0.97, 0.88))
	lantern.draw_arc(_light_pos, 12.5, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 1.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _starting:
		# A near miss on "Click again to erase" only backs out of erasing.
		if _confirm_left > 0.0:
			_confirm_left = 0.0
			_style_start_over()
			return
		_starting = true
		_radius = STRIKE_RADIUS
		await get_tree().create_timer(0.35).timeout
		var next := "res://scenes/lamp_tree.tscn" if SaveGame.exists(save_path) and _between_nights() else "res://scenes/night.tscn"
		get_tree().change_scene_to_file(next)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
