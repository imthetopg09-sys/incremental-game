extends Control
## Title screen: a lantern follows the mouse over a dark square. Click to begin.

const BASE_RADIUS := 220.0
const STRIKE_RADIUS := 360.0
const LIGHT_FOLLOW := 12.0
const LIGHT_COLOR := Color(1.0, 0.68, 0.32)

@onready var night: ColorRect = $Night
@onready var lantern: Control = $Lantern
@onready var version_label: Label = $Version

var _light_pos := Vector2.ZERO
var _radius := BASE_RADIUS
var _starting := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	lantern.draw.connect(_draw_lantern)
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_light_pos = size * 0.5
	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("light_count", 1)
	mat.set_shader_parameter("light_colors", PackedVector4Array([Vector4(LIGHT_COLOR.r, LIGHT_COLOR.g, LIGHT_COLOR.b, 1.0)]))


func _process(delta: float) -> void:
	var target := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(target):
		target = size * 0.5
	# Frame-rate independent easing toward the cursor.
	_light_pos = _light_pos.lerp(target, 1.0 - exp(-LIGHT_FOLLOW * delta))
	_radius = lerpf(_radius, BASE_RADIUS, 1.0 - exp(-3.0 * delta))

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
		_starting = true
		_radius = STRIKE_RADIUS
		await get_tree().create_timer(0.35).timeout
		get_tree().change_scene_to_file("res://scenes/night.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
