extends Control
## Title screen placeholder: a lantern that follows the mouse over a dark square.
## The real night (step 2 of the plan) replaces the click handler.

const BASE_RADIUS := 220.0
const STRIKE_RADIUS := 360.0
const LIGHT_FOLLOW := 12.0

@onready var night: ColorRect = $Night
@onready var version_label: Label = $Version

var _light_pos := Vector2.ZERO
var _radius := BASE_RADIUS


func _ready() -> void:
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	_light_pos = size * 0.5


func _process(delta: float) -> void:
	var target := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(target):
		target = size * 0.5
	# Frame-rate independent easing toward the cursor.
	_light_pos = _light_pos.lerp(target, 1.0 - exp(-LIGHT_FOLLOW * delta))
	_radius = lerpf(_radius, BASE_RADIUS, 1.0 - exp(-3.0 * delta))

	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("light_pos", _light_pos)
	mat.set_shader_parameter("rect_size", night.size)
	mat.set_shader_parameter("radius", _radius)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_radius = STRIKE_RADIUS
