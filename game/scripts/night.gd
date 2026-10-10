extends Node2D
## One night: feeds input to NightSim at a fixed rate and draws it.
## Death and dawn overlays decide what happens to the run's Echo, then the night restarts.

enum State { PLAYING, PAUSED, DEVELOPING, CHOOSING, WAITING }

const PLAYER_COLOR := Color(1.0, 0.72, 0.36)
const SHADOW_BODY := Color(0.025, 0.02, 0.035)
const SHADOW_EYES := Color(0.88, 0.9, 1.0, 0.55)
const BURN_RIM := Color(1.0, 0.55, 0.18)
const ECHO_ALPHA := 0.4
const FX_LIFE := 0.45
const HOUR_LINES := {
	1: "1 AM. Something faster is circling.",
	2: "2 AM. The heavy ones wake.",
	3: "3 AM. The night leans closer.",
	4: "4 AM. Hold on.",
	5: "5 AM. Almost dawn.",
}

@onready var background: ColorRect = $Background
@onready var dim: ColorRect = $Dim
@onready var trails: Node2D = $Trails
@onready var entities: Node2D = $Entities
@onready var clock_label: Label = %Clock
@onready var run_label: Label = %RunInfo
@onready var burned_label: Label = %Burned
@onready var toast_label: Label = %Toast
@onready var flame_bar: Control = %FlameBar
@onready var overlay: Control = %Overlay
@onready var overlay_title: Label = %OverlayTitle
@onready var overlay_body: Label = %OverlayBody
@onready var overlay_hint: Label = %OverlayHint
@onready var choices: VBoxContainer = %Choices

var sim: NightSim
var state := State.PLAYING
var _fx: Array[Dictionary] = []
var _toast_time := 0.0
var _overlay_time := 0.0
var _highlight: EchoRecording = null
var _render_time := 0.0
## Dev flags (pass after `--` on the command line): --autopilot, --demo-echoes=N,
## --skip-to=SECONDS. Used for screenshots and footage.
var _autopilot: Bot = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--autopilot"):
		_autopilot = Bot.new("kite")
	for a in args:
		if a.begins_with("--demo-echoes=") and GameState.run_number == 1:
			GameState.make_demo_echoes(int(a.get_slice("=", 1)))
	sim = NightSim.new(GameState.echoes.duplicate(), Tuning.NIGHT_SEED, GameState.run_number)
	for a in args:
		if a.begins_with("--skip-to="):
			var until := float(a.get_slice("=", 1))
			var bot := Bot.new("kite")
			while sim.t < until and not sim.is_over():
				sim.step(1.0 / 60.0, bot.steer(sim))
			if sim.is_over():
				_end_run.call_deferred(sim.alive == false)
	trails.draw.connect(_draw_trails)
	entities.draw.connect(_draw_entities)
	flame_bar.draw.connect(_draw_flame_bar)
	overlay.visible = false
	toast_label.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_show_toast("Run %d. It is midnight." % GameState.run_number if GameState.run_number > 1 else "It is midnight. It is always midnight.")
	_update_hud()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	sim.step(delta, _steer_target())
	for e in sim.events:
		_on_event(e)


func _process(delta: float) -> void:
	_render_time += delta
	for fx in _fx:
		fx["age"] += delta
	_fx = _fx.filter(func(fx): return fx["age"] < FX_LIFE)
	_toast_time += delta
	if state == State.PAUSED:
		toast_label.modulate.a = 1.0
	else:
		toast_label.modulate.a = clampf(2.5 - _toast_time, 0.0, 1.0) * clampf(_toast_time * 3.0, 0.0, 1.0)
	if overlay.visible:
		_overlay_time += delta
		overlay.modulate.a = clampf(_overlay_time * 2.0, 0.0, 1.0)
		dim.color.a = 0.6 * overlay.modulate.a
		overlay_hint.visible = state == State.WAITING and _overlay_time > 1.0
	_update_lights()
	_update_hud()
	trails.queue_redraw()
	entities.queue_redraw()
	flame_bar.queue_redraw()


func _steer_target() -> Vector2:
	if _autopilot != null:
		return _autopilot.steer(sim)
	var keys := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	keys += Vector2(
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if keys != Vector2.ZERO:
		return sim.player_pos + keys.normalized() * 100.0
	return get_global_mouse_position()


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"burn":
			var color := PLAYER_COLOR if e["light"] < 0 else sim.echoes[e["light"]].hue()
			_fx.append({"pos": e["pos"], "age": 0.0, "color": color, "big": e["kind"] == "bloat"})
		"hour":
			_show_toast(HOUR_LINES.get(e["hour"], ""))
		"death":
			_end_run(true)
		"dawn":
			_end_run(false)


func _show_toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 0.0


# --- End of a run ---------------------------------------------------------------

func _end_run(died: bool) -> void:
	state = State.DEVELOPING
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rec := sim.recording
	_overlay_time = 0.0
	overlay.visible = true
	overlay.modulate.a = 0.0
	if died:
		overlay_title.text = "Midnight, again."
		overlay_body.text = "You held the night until %s.   %d shadows burned." % [NightClock.label(rec.duration), sim.burned]
	else:
		overlay_title.text = "6:00 AM. You held the night."
		overlay_body.text = "Dawn is coming. %d shadows burned." % sim.burned
	await get_tree().create_timer(1.0).timeout
	if GameState.try_keep(rec):
		overlay_body.text += "\nThis run will walk beside you as an Echo."
		state = State.WAITING
	else:
		_show_choices(rec)


func _show_choices(new_rec: EchoRecording) -> void:
	state = State.CHOOSING
	overlay_body.text += "\nYour Sconces are full. Which light do you let go?"
	var candidates: Array[EchoRecording] = GameState.echoes.duplicate()
	candidates.append(new_rec)
	for rec in candidates:
		var b := Button.new()
		var tag := "  (this run)" if rec == new_rec else ""
		var reach := NightClock.label(rec.duration) if rec.died else "dawn"
		b.text = "Run %d   held until %s   %d burned%s" % [rec.run_number, reach, rec.burned, tag]
		b.add_theme_color_override("font_color", rec.hue() if rec != new_rec else PLAYER_COLOR)
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(420, 44)
		b.mouse_entered.connect(func(): _highlight = rec)
		b.mouse_exited.connect(func():
			if _highlight == rec:
				_highlight = null)
		b.pressed.connect(func(): _choose(rec, new_rec))
		choices.add_child(b)


func _choose(chosen: EchoRecording, new_rec: EchoRecording) -> void:
	GameState.let_go_of(chosen, new_rec)
	_next_run()


func _next_run() -> void:
	GameState.begin_next_run()
	get_tree().reload_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if state == State.PLAYING:
			state = State.PAUSED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_show_toast("Paused. Esc to resume, Q to quit.")
		elif state == State.PAUSED:
			state = State.PLAYING
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_toast_time = 2.5
	elif state == State.PAUSED and event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
		get_tree().quit()
	elif state == State.WAITING and _overlay_time > 1.0 and event is InputEventMouseButton and event.pressed:
		_next_run()


# --- Drawing -------------------------------------------------------------------

func _update_lights() -> void:
	var lights := PackedVector4Array()
	var colors := PackedVector4Array()
	var flicker := 0.94 + 0.04 * sin(_render_time * 13.0) + 0.02 * sin(_render_time * 31.0 + 1.7)
	var player_visual := sim.light_radius() * 1.55 * flicker
	lights.append(Vector4(sim.player_pos.x, sim.player_pos.y, player_visual, 1.0 if sim.alive else 0.25))
	colors.append(Vector4(PLAYER_COLOR.r, PLAYER_COLOR.g, PLAYER_COLOR.b, 1.0))
	for i in sim.active_echoes():
		if lights.size() >= 16:
			break
		var p := sim.echoes[i].position_at(sim.t)
		var c := sim.echoes[i].hue()
		lights.append(Vector4(p.x, p.y, Tuning.ECHO_LIGHT_RADIUS * 1.5, 0.85))
		colors.append(Vector4(c.r, c.g, c.b, 1.0))
	var mat := background.material as ShaderMaterial
	mat.set_shader_parameter("lights", lights)
	mat.set_shader_parameter("light_colors", colors)
	mat.set_shader_parameter("light_count", lights.size())
	mat.set_shader_parameter("rect_size", background.size)


## Additive layer: long-exposure trails and foresight lines.
func _draw_trails() -> void:
	var t := sim.t
	for i in sim.echoes.size():
		var rec := sim.echoes[i]
		var c := rec.hue()
		var highlighted := rec == _highlight
		# The whole route so far, faint, like a long-exposure photo.
		var past := rec.path_between(0.0, t if state == State.PLAYING else rec.duration)
		if past.size() >= 2:
			trails.draw_polyline(past, Color(c, 0.5 if highlighted else 0.09), 3.0 if highlighted else 2.0, true)
		if not rec.is_active(t) or state != State.PLAYING:
			continue
		var recent := rec.path_between(t - 1.0, t)
		if recent.size() >= 2:
			trails.draw_polyline(recent, Color(c, 0.45), 3.0, true)
		# Foresight: dots showing where this Echo is about to walk.
		var steps := 10
		for k in range(1, steps + 1):
			var ft := t + Tuning.FORESIGHT_SECONDS * k / steps
			if ft > rec.duration:
				break
			trails.draw_circle(rec.position_at(ft), 2.2, Color(c, 0.55 * (1.0 - float(k) / (steps + 1))))
		if rec.duration - t < Tuning.FORESIGHT_SECONDS and rec.died:
			# Mark where this Echo will go out.
			var end := rec.position_at(rec.duration)
			trails.draw_arc(end, 9.0, 0.0, TAU, 20, Color(c, 0.5), 1.5, true)

	# The living lantern's own trail, or its whole run once the night is over.
	if state == State.PLAYING or state == State.PAUSED:
		var mine := sim.recording.path_between(maxf(0.0, t - 2.5), t)
		if mine.size() >= 2:
			trails.draw_polyline(mine, Color(PLAYER_COLOR, 0.35), 3.0, true)
	else:
		var whole := sim.recording.path_between(0.0, sim.recording.duration)
		var a := 0.85 if _highlight == null or _highlight == sim.recording else 0.25
		if whole.size() >= 2:
			trails.draw_polyline(whole, Color(PLAYER_COLOR, a * clampf(_overlay_time, 0.0, 1.0)), 2.5, true)

	for fx in _fx:
		var k: float = fx["age"] / FX_LIFE
		var r: float = lerpf(6.0, 34.0 if fx["big"] else 22.0, k)
		trails.draw_arc(fx["pos"], r, 0.0, TAU, 24, Color(fx["color"], 0.8 * (1.0 - k)), 2.0, true)


func _draw_entities() -> void:
	var t := sim.t
	for s in sim.shadows:
		var wob := 1.0 + 0.06 * sin(_render_time * 5.0 + s.phase)
		var r := s.radius * wob
		entities.draw_circle(s.pos, r, SHADOW_BODY)
		if s.burning < 0.12:
			var heat := 0.5 + 0.5 * sin(_render_time * 40.0 + s.phase)
			entities.draw_arc(s.pos, r, 0.0, TAU, 20, Color(BURN_RIM, 0.45 + 0.4 * heat), 2.0, true)
		var side := s.facing.orthogonal() * r * 0.38
		var fwd := s.facing * r * 0.25
		var eye := maxf(1.6, r * 0.14)
		entities.draw_circle(s.pos + fwd + side, eye, SHADOW_EYES)
		entities.draw_circle(s.pos + fwd - side, eye, SHADOW_EYES)

	if state == State.PLAYING or state == State.PAUSED:
		for i in sim.active_echoes():
			var rec := sim.echoes[i]
			var p := rec.position_at(t)
			var c := rec.hue()
			entities.draw_circle(p, 11.0, Color(c, ECHO_ALPHA * 0.35))
			entities.draw_circle(p, 7.5, Color(c, ECHO_ALPHA))
			entities.draw_circle(p, 3.5, Color(1, 1, 1, ECHO_ALPHA + 0.15))

	if sim.alive:
		var p := sim.player_pos
		entities.draw_circle(p, Tuning.PLAYER_RADIUS, Color(PLAYER_COLOR, 1.0))
		entities.draw_circle(p, Tuning.PLAYER_RADIUS * 0.5, Color(1.0, 0.97, 0.88))
		entities.draw_arc(p, Tuning.PLAYER_RADIUS + 2.5, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 1.5, true)
		if state == State.PLAYING and _autopilot == null:
			# Where the mouse is steering the lantern.
			entities.draw_arc(get_global_mouse_position(), 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.35), 1.0, true)


func _draw_flame_bar() -> void:
	var size := flame_bar.size
	var f := clampf(sim.flame / sim.max_flame, 0.0, 1.0)
	flame_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
	var low := f < 0.3 and int(_render_time * 4.0) % 2 == 0
	flame_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * f, size.y)), Color(1.0, 0.35, 0.2) if low else PLAYER_COLOR)


func _update_hud() -> void:
	clock_label.text = NightClock.label(sim.t)
	run_label.text = "Run %d    Echoes %d / %d" % [GameState.run_number, sim.echoes.size(), GameState.sconces]
	burned_label.text = "%d burned" % sim.burned
