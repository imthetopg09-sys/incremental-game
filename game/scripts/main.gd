extends Control
## Title screen: a lantern follows the mouse over a dark square. Click to begin.
## With a save on disk the click continues it, and "Start over" (two clicks) erases it.

const BASE_RADIUS := 220.0
const STRIKE_RADIUS := 360.0
const LIGHT_FOLLOW := 12.0
const LIGHT_COLOR := Color(1.0, 0.68, 0.32)
const HINT_NEW := "Click to strike a match. Esc quits."
const HINT_CONTINUE := "Click to continue: Run %d. Esc quits."
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


func _refresh_save_ui() -> void:
	var has_save := SaveGame.exists(save_path)
	hint_label.text = HINT_CONTINUE % GameState.run_number if has_save else HINT_NEW
	start_over.visible = has_save
	_confirm_left = 0.0
	_style_start_over()


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
		get_tree().change_scene_to_file("res://scenes/night.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
