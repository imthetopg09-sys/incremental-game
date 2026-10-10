extends Node2D
## One night: feeds input to NightSim at a fixed rate and draws it.
## Death and dawn overlays decide what happens to the run's Echo, then the night restarts.
##
## Draw order: Background (light shader), Trails (long exposure), Entities (shadows,
## Echoes, lantern), FX (foresight dots, burn rings), Dim and Develop (the end-of-run
## route), then the HUD.

enum State { PLAYING, PAUSED, LEVEL_UP, DEVELOPING, CHOOSING, WAITING }

const PLAYER_COLOR := Color(1.0, 0.72, 0.36)
const SHADOW_BODY := Color(0, 0, 0)
const SHADOW_EYES := Color(0.88, 0.9, 1.0, 0.6)
const CREEPER_EYES := Color(1.0, 0.62, 0.32, 0.75)
const BURN_RIM := Color(1.0, 0.55, 0.18)
const ECHO_ALPHA := 0.4
const ECHO_LIGHT := 0.6
const FX_LIFE := 0.45
## How long the long-exposure route takes to fade, and how long a spent Echo lingers.
const ROUTE_FADE := 20.0
const ROUTE_WINDOW := 45.0
const SPENT_FADE := 3.0
const HOUR_LINES := {
	1: "1 AM. Something faster is circling.",
	2: "2 AM. The heavy ones wake.",
	3: "3 AM. The night leans closer.",
	4: "4 AM. Hold on.",
	5: "5 AM. Almost dawn.",
}
const STEER_KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]

@onready var background: ColorRect = $Background
@onready var trails: Node2D = $Trails
@onready var entities: Node2D = $Entities
@onready var fx_layer: Node2D = $FX
@onready var dim: ColorRect = $Dim
@onready var develop: Node2D = $Develop
@onready var hud_top: Array[Control] = [%Clock, %RunInfo, %Burned, %FlameBar]
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
var _paused_at := 0.0
var _highlight: EchoRecording = null
var _render_time := 0.0
var _mouse_steer := true
var _sparks: Array[Dictionary] = []  # {points, age, color}
var _level_panel: PanelContainer = null
var _tallow_earned := 0
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
	sim = NightSim.new(GameState.all_recordings(), Tuning.NIGHT_SEED, GameState.run_number, GameState.stats())
	for a in args:
		if a.begins_with("--skip-to="):
			var until := float(a.get_slice("=", 1))
			var bot := Bot.new("kite")
			while sim.t < until and not sim.is_over():
				if sim.pending_level_ups > 0:
					sim.pick_boon(bot.pick_boon(sim))
				sim.step(1.0 / 60.0, bot.steer(sim))
			if sim.is_over():
				_end_run.call_deferred(not sim.alive)
	trails.draw.connect(_draw_trails)
	entities.draw.connect(_draw_entities)
	fx_layer.draw.connect(_draw_fx)
	develop.draw.connect(_draw_develop)
	flame_bar.draw.connect(_draw_flame_bar)
	overlay.visible = false
	toast_label.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_show_toast("Run %d. It is midnight." % GameState.run_number if GameState.run_number > 1 else "It is midnight. It is always midnight.")
	_update_hud()
	Sfx.strike()
	if state == State.PLAYING:
		_check_level_up.call_deferred()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == State.PLAYING and _autopilot == null:
			_set_paused(true)


func _physics_process(delta: float) -> void:
	if state != State.PLAYING:
		return
	sim.step(delta, _steer_target())
	for e in sim.events:
		_on_event(e)
	_check_level_up()


func _process(delta: float) -> void:
	_render_time += delta
	for fx in _fx:
		fx["age"] += delta
	_fx = _fx.filter(func(fx): return fx["age"] < FX_LIFE)
	for sp in _sparks:
		sp["age"] += delta
	_sparks = _sparks.filter(func(sp): return sp["age"] < 0.25)
	_toast_time += delta
	if state == State.PAUSED:
		toast_label.modulate.a = 1.0
	else:
		toast_label.modulate.a = clampf(2.5 - _toast_time, 0.0, 1.0) * clampf(_toast_time * 3.0, 0.0, 1.0)
	if overlay.visible:
		_overlay_time += delta
		var a := clampf(_overlay_time * 2.0, 0.0, 1.0)
		overlay.modulate.a = a
		dim.color.a = 0.6 * a
		develop.modulate.a = clampf(_overlay_time, 0.0, 1.0)
		overlay_hint.visible = state == State.WAITING and _overlay_time > 1.0
		for c in hud_top:
			c.modulate.a = 1.0 - a
	else:
		_fade_hud_near_lantern()
	_update_lights()
	_update_hud()
	# The end screen is static: only redraw the world while the night is live.
	if not overlay.visible:
		trails.queue_redraw()
		entities.queue_redraw()
		fx_layer.queue_redraw()
	flame_bar.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_steer = true
	elif event is InputEventKey and event.pressed and STEER_KEYS.has(event.physical_keycode):
		_mouse_steer = false


func _steer_target() -> Vector2:
	if _autopilot != null:
		return _autopilot.steer(sim)
	var keys := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
	if keys != Vector2.ZERO:
		return sim.player_pos + keys.normalized() * 100.0
	# Keyboard players stand still when they let go; mouse players follow the cursor.
	return get_global_mouse_position() if _mouse_steer else sim.player_pos


func _on_event(e: Dictionary) -> void:
	match e["type"]:
		"burn":
			var color := PLAYER_COLOR if e["light"] < 0 else sim.echoes[e["light"]].hue()
			_fx.append({"pos": e["pos"], "age": 0.0, "color": color, "big": e["kind"] == "bloat"})
			Sfx.burn(-1 if e["light"] < 0 else sim.echoes[e["light"]].hue_index, e["kind"] == "bloat")
		"spark":
			var color := PLAYER_COLOR if e["light"] < 0 else sim.echoes[e["light"]].hue()
			_sparks.append({"points": e["points"], "age": 0.0, "color": color})
		"level_up":
			Sfx.level_up()
		"hour":
			_show_toast(HOUR_LINES.get(e["hour"], ""))
		"death":
			Sfx.death()
			_end_run(true)
		"dawn":
			Sfx.dawn()
			_end_run(false)


func _show_toast(text: String) -> void:
	toast_label.text = text
	_toast_time = 0.0


func _set_paused(on: bool) -> void:
	if on and state == State.PLAYING:
		state = State.PAUSED
		_paused_at = _render_time
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_show_toast("Paused. Click or press Esc to resume. Q quits.")
	elif not on and state == State.PAUSED:
		state = State.PLAYING
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		_toast_time = 2.5


# --- Level-ups ------------------------------------------------------------------

## Pauses the night and offers three Boons whenever a level-up is waiting.
func _check_level_up() -> void:
	if sim.pending_level_ups <= 0 or sim.is_over() or state != State.PLAYING:
		return
	if _autopilot != null:
		while sim.pending_level_ups > 0:
			sim.pick_boon(_autopilot.pick_boon(sim))
		return
	state = State.LEVEL_UP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_level_choices()


func _show_level_choices() -> void:
	if _level_panel != null:
		_level_panel.queue_free()
	_level_panel = PanelContainer.new()
	_level_panel.add_theme_stylebox_override("panel", _choice_box(PLAYER_COLOR, 0.0, 0.88))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_level_panel.add_child(box)
	var title := Label.new()
	title.text = "The flame grows. Choose a Boon." if sim.t > 0.0 else "Kindling. Choose a Boon."
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.62))
	box.add_child(title)
	var note := Label.new()
	note.text = "Your Echo will take the same Boon at this moment, every night."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 15)
	note.add_theme_color_override("font_color", Color(0.85, 0.78, 0.68, 0.75))
	box.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var offer := sim.offer()
	for i in offer.size():
		var id: String = offer[i]
		var info := Upgrades.boon(id)
		var lv: int = sim.boons.get(id, 0)
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 150)
		b.text = "%s\n\n%s\n\n%s   [%d]" % [info["name"], info["desc"],
			"New" if lv == 0 else "Level %d" % (lv + 1), i + 1]
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Color(1, 0.9, 0.75))
		b.add_theme_color_override("font_hover_color", Color(1, 0.97, 0.9))
		b.add_theme_stylebox_override("normal", _choice_box(PLAYER_COLOR, 0.25))
		b.add_theme_stylebox_override("hover", _choice_box(PLAYER_COLOR, 0.8))
		b.add_theme_stylebox_override("focus", _choice_box(PLAYER_COLOR, 0.8))
		b.add_theme_stylebox_override("pressed", _choice_box(PLAYER_COLOR, 1.0))
		b.pressed.connect(func(): _pick(id))
		row.add_child(b)
	$HUD.add_child(_level_panel)
	_level_panel.reset_size()
	_level_panel.position = (Tuning.ARENA_SIZE - _level_panel.size) * 0.5
	_level_panel.set_meta("offer", offer)


func _pick(id: String) -> void:
	if state != State.LEVEL_UP:
		return
	Sfx.ui_click()
	sim.pick_boon(id)
	if sim.pending_level_ups > 0:
		_show_level_choices()
		return
	_level_panel.queue_free()
	_level_panel = null
	state = State.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


# --- End of a run ---------------------------------------------------------------

func _end_run(died: bool) -> void:
	state = State.DEVELOPING
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var rec := sim.recording
	_overlay_time = 0.0
	overlay.visible = true
	overlay.modulate.a = 0.0
	develop.modulate.a = 0.0
	trails.queue_redraw()
	entities.queue_redraw()
	fx_layer.queue_redraw()
	develop.queue_redraw()
	_tallow_earned = GameState.award(sim.burned_by_kind)
	if died:
		overlay_title.text = "Midnight, again."
		overlay_body.text = "You held the night until %s.   %d shadows burned.   +%d Tallow" % [NightClock.label(rec.duration), sim.burned, _tallow_earned]
	else:
		overlay_title.text = "6:00 AM. You held the night."
		overlay_body.text = "Dawn is coming. %d shadows burned.   +%d Tallow" % [sim.burned, _tallow_earned]
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
		var is_new := rec == new_rec
		var reach := NightClock.label(rec.duration) if rec.died else "dawn"
		b.text = "Run %d   held until %s   %d burned%s" % [rec.run_number, reach, rec.burned, "  (this run)" if is_new else ""]
		var hue := PLAYER_COLOR if is_new else rec.hue()
		b.add_theme_color_override("font_color", hue)
		b.add_theme_color_override("font_hover_color", hue.lightened(0.25))
		b.add_theme_color_override("font_focus_color", hue.lightened(0.25))
		b.add_theme_color_override("font_pressed_color", hue.lightened(0.4))
		b.add_theme_stylebox_override("normal", _choice_box(hue, 0.15))
		b.add_theme_stylebox_override("hover", _choice_box(hue, 0.6))
		b.add_theme_stylebox_override("focus", _choice_box(hue, 0.6))
		b.add_theme_stylebox_override("pressed", _choice_box(hue, 0.8))
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(460, 44)
		b.mouse_entered.connect(func():
			_highlight = rec
			develop.queue_redraw())
		b.mouse_exited.connect(func():
			if _highlight == rec:
				_highlight = null
				develop.queue_redraw())
		b.pressed.connect(func(): _choose(rec, new_rec))
		choices.add_child(b)


## Saves the end-of-run screen as a PNG in the player's Pictures folder.
func _save_postcard() -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "":
		dir = OS.get_user_data_dir()
	var path := dir.path_join("Midnight Again - Run %d.png" % sim.recording.run_number)
	if img.save_png(path) == OK:
		_show_toast("Postcard saved to %s" % path)
	else:
		_show_toast("Could not save the postcard.")


func _choice_box(hue: Color, border_alpha: float, bg_alpha := 0.06) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(hue, bg_alpha) if bg_alpha < 0.5 else Color(0.015, 0.012, 0.02, bg_alpha)
	box.border_color = Color(hue, border_alpha)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(14)
	return box


func _choose(chosen: EchoRecording, new_rec: EchoRecording) -> void:
	GameState.let_go_of(chosen, new_rec)
	_next_run()


## After a night: on to the Lamp Tree, where the next night is lit.
func _next_run() -> void:
	GameState.begin_next_run()
	get_tree().change_scene_to_file("res://scenes/lamp_tree.tscn")


func _unhandled_input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if overlay.visible and event is InputEventKey and event.pressed and event.keycode == KEY_P:
		_save_postcard()
		return
	match state:
		State.PLAYING:
			if event.is_action_pressed("ui_cancel"):
				_set_paused(true)
		State.PAUSED:
			# Ignore the click that refocuses the window right after an auto-pause.
			if event.is_action_pressed("ui_cancel") or (click and _render_time - _paused_at > 0.3):
				_set_paused(false)
			elif event is InputEventKey and event.pressed and event.keycode == KEY_Q:
				get_tree().quit()
		State.LEVEL_UP:
			if event is InputEventKey and event.pressed and _level_panel != null:
				var idx: int = event.keycode - KEY_1
				var offer: Array = _level_panel.get_meta("offer", [])
				if idx >= 0 and idx < offer.size():
					_pick(offer[idx])
		State.WAITING:
			if _overlay_time > 1.0 and (click or event.is_action_pressed("ui_accept")):
				_next_run()
			elif event.is_action_pressed("ui_cancel"):
				GameState.begin_next_run()
				get_tree().change_scene_to_file("res://scenes/main.tscn")


# --- Drawing -------------------------------------------------------------------

## How far between the last two physics steps this frame is, for smooth motion.
func _frac() -> float:
	return Engine.get_physics_interpolation_fraction() if state == State.PLAYING else 1.0


func _draw_time() -> float:
	return maxf(0.0, sim.t - (1.0 - _frac()) / Engine.physics_ticks_per_second)


func _player_draw_pos() -> Vector2:
	return sim.prev_player_pos.lerp(sim.player_pos, _frac())


func _live() -> bool:
	return state == State.PLAYING or state == State.PAUSED


func _update_lights() -> void:
	var lights := PackedVector4Array()
	var colors := PackedVector4Array()
	var flicker := 0.97 + 0.02 * sin(_render_time * 13.0) + 0.01 * sin(_render_time * 31.0 + 1.7)
	var p := _player_draw_pos()
	lights.append(Vector4(p.x, p.y, sim.light_radius() * flicker, 1.0 if sim.alive else 0.25))
	colors.append(Vector4(PLAYER_COLOR.r, PLAYER_COLOR.g, PLAYER_COLOR.b, 1.0))
	if _live():
		var t := _draw_time()
		for i in sim.active_echoes():
			if lights.size() >= 16:
				break
			var e := sim.echoes[i].position_at(t)
			var c := sim.echoes[i].hue()
			lights.append(Vector4(e.x, e.y, sim.echo_light_radius(), ECHO_LIGHT))
			colors.append(Vector4(c.r, c.g, c.b, 1.0))
		for i in sim.glowing_echoes():
			if lights.size() >= 16:
				break
			var rec := sim.echoes[i]
			var g := rec.position_at(rec.duration)
			var c := rec.hue()
			lights.append(Vector4(g.x, g.y, sim.echo_light_radius() * 0.8, ECHO_LIGHT * 0.7))
			colors.append(Vector4(c.r, c.g, c.b, 1.0))
		for w in sim.wax:
			if lights.size() >= 16:
				break
			# Only the freshest wax adds light; the rest is drawn as glowing pools.
			if w["age"] < 0.5:
				var c := PLAYER_COLOR if w["light"] < 0 else sim.echoes[w["light"]].hue()
				lights.append(Vector4(w["pos"].x, w["pos"].y, Tuning.CANDLE_RADIUS * 2.0, 0.25))
				colors.append(Vector4(c.r, c.g, c.b, 1.0))
	var mat := background.material as ShaderMaterial
	mat.set_shader_parameter("lights", lights)
	mat.set_shader_parameter("light_colors", colors)
	mat.set_shader_parameter("light_count", lights.size())
	mat.set_shader_parameter("rect_size", background.size)


## Long exposure: each Echo's recent route fades out over ROUTE_FADE seconds, and
## a spent Echo's whole route fades away shortly after it goes out.
func _draw_trails() -> void:
	if not _live():
		return
	var t := _draw_time()
	for rec in sim.echoes:
		var c := rec.hue()
		var spent := clampf(1.0 - (t - rec.duration) / SPENT_FADE, 0.0, 1.0) if t > rec.duration else 1.0
		if spent <= 0.0:
			continue
		var from := maxf(0.0, t - ROUTE_WINDOW)
		var to := minf(t, rec.duration)
		var path := rec.path_between(from, to)
		if path.size() >= 2:
			var step := 2
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			for k in range(0, path.size(), step):
				var age := (path.size() - 1 - k) / EchoRecording.RATE
				pts.append(path[k])
				cols.append(Color(c, 0.12 * exp(-age / ROUTE_FADE) * spent))
			pts.append(path[path.size() - 1])
			cols.append(Color(c, 0.12 * spent))
			trails.draw_polyline_colors(pts, cols, 2.0, false)
		if rec.is_active(t):
			var recent := rec.path_between(t - 1.0, t)
			if recent.size() >= 2:
				trails.draw_polyline(recent, Color(c, 0.3), 3.0, true)

	for w in sim.wax:
		var c := PLAYER_COLOR if w["light"] < 0 else sim.echoes[w["light"]].hue()
		var k: float = w["age"] / w["life"]
		trails.draw_circle(w["pos"], Tuning.CANDLE_RADIUS * (0.7 + 0.3 * k), Color(c, 0.22 * (1.0 - k)))
		trails.draw_circle(w["pos"], Tuning.CANDLE_RADIUS * 0.35, Color(1, 0.95, 0.8, 0.25 * (1.0 - k)))

	var mine := sim.recording.path_between(maxf(0.0, t - 2.5), sim.t)
	mine.append(_player_draw_pos())
	if mine.size() >= 2:
		trails.draw_polyline(mine, Color(PLAYER_COLOR, 0.45), 3.0, true)


## Foresight dots, where Echoes will go out, and burn rings.
func _draw_fx() -> void:
	if _live():
		var t := _draw_time()
		for rec in sim.echoes:
			var c := rec.hue()
			if rec.is_active(t):
				var steps := 10
				for k in range(1, steps + 1):
					var ft: float = t + sim.stats["foresight"] * k / steps
					if ft > rec.duration:
						break
					fx_layer.draw_circle(rec.position_at(ft), 2.2, Color(c, 0.55 * (1.0 - float(k) / (steps + 1))))
				if rec.died and rec.duration - t < sim.stats["foresight"]:
					fx_layer.draw_arc(rec.position_at(rec.duration), 9.0, 0.0, TAU, 20, Color(c, 0.5), 1.5, true)
			elif rec.died and t - rec.duration < SPENT_FADE:
				# A small ring marks where a spent Echo went out.
				var a := 1.0 - (t - rec.duration) / SPENT_FADE
				fx_layer.draw_arc(rec.position_at(rec.duration), 9.0, 0.0, TAU, 20, Color(c, 0.45 * a), 1.5, true)
	if _live():
		for c in sim.casters:
			var hue: Color = PLAYER_COLOR if c["light"] < 0 else sim.echoes[c["light"]].hue()
			var a := 1.0 if c["light"] < 0 else 0.6
			for m in sim.moth_positions(c):
				var flap := 0.6 + 0.4 * absf(sin(_render_time * 18.0 + m.x * 0.05))
				fx_layer.draw_circle(m, Tuning.MOTH_RADIUS * 0.9, Color(hue, 0.25 * a))
				fx_layer.draw_circle(m, 2.5 * flap + 1.0, Color(1, 0.95, 0.85, 0.85 * a))
		for b in sim.bolts:
			var hue: Color = PLAYER_COLOR if b["light"] < 0 else sim.echoes[b["light"]].hue()
			var p: Vector2 = b["prev_pos"].lerp(b["pos"], _frac())
			var dir: Vector2 = (b["pos"] - b["prev_pos"])
			fx_layer.draw_line(p - dir * 2.5, p, Color(hue, 0.6), 3.0, true)
			fx_layer.draw_circle(p, 3.5, Color(1, 0.97, 0.9, 0.95))
	for sp in _sparks:
		var a: float = 1.0 - sp["age"] / 0.25
		var pts: PackedVector2Array = sp["points"]
		var jag := PackedVector2Array()
		for i in pts.size() - 1:
			jag.append(pts[i])
			var mid := pts[i].lerp(pts[i + 1], 0.5)
			var n := (pts[i + 1] - pts[i]).orthogonal().normalized()
			jag.append(mid + n * sin(_render_time * 70.0 + i * 3.0) * 9.0)
		jag.append(pts[pts.size() - 1])
		fx_layer.draw_polyline(jag, Color(sp["color"], 0.5 * a), 4.0, true)
		fx_layer.draw_polyline(jag, Color(1, 1, 1, 0.9 * a), 1.5, true)

	for fx in _fx:
		var k: float = fx["age"] / FX_LIFE
		var r: float = lerpf(6.0, 34.0 if fx["big"] else 22.0, k)
		fx_layer.draw_arc(fx["pos"], r, 0.0, TAU, 24, Color(fx["color"], 0.8 * (1.0 - k)), 2.0, true)


func _draw_entities() -> void:
	var frac := _frac()
	for s in sim.shadows:
		var pos := s.prev_pos.lerp(s.pos, frac)
		var wob := 1.0 + 0.06 * sin(_render_time * 5.0 + s.phase)
		var r := s.radius * wob
		var f := s.facing
		var side := f.orthogonal()
		match s.kind:
			"creeper":
				# A comet: fast, with a tail and narrow ember eyes.
				entities.draw_circle(pos - f * r * 1.6, r * 0.45, SHADOW_BODY)
				entities.draw_circle(pos - f * r * 0.9, r * 0.7, SHADOW_BODY)
				entities.draw_circle(pos, r, SHADOW_BODY)
				_draw_rim(s, pos, r)
				for sgn in [-1.0, 1.0]:
					var e: Vector2 = pos + f * r * 0.35 + side * r * 0.32 * sgn
					entities.draw_line(e - side * 1.8 * sgn, e + side * 1.8 * sgn + f * 0.6, CREEPER_EYES, 1.6, true)
			"bloat":
				# Swollen and pulsing, with four eyes: it will split.
				r *= 1.0 + 0.1 * sin(_render_time * 2.2 + s.phase)
				entities.draw_circle(pos, r, SHADOW_BODY)
				_draw_rim(s, pos, r)
				for k in 4:
					var ang := -0.75 + 0.5 * k
					var e := pos + f.rotated(ang) * r * 0.45
					entities.draw_circle(e, 2.0, SHADOW_EYES)
			"mite":
				entities.draw_circle(pos, r, SHADOW_BODY)
				_draw_rim(s, pos, r)
				entities.draw_circle(pos + f * r * 0.3, 2.0, SHADOW_EYES)
			_:
				entities.draw_circle(pos, r, SHADOW_BODY)
				_draw_rim(s, pos, r)
				var eye := maxf(2.0, r * 0.14)
				entities.draw_circle(pos + f * r * 0.25 + side * r * 0.38, eye, SHADOW_EYES)
				entities.draw_circle(pos + f * r * 0.25 - side * r * 0.38, eye, SHADOW_EYES)

	if _live():
		var t := _draw_time()
		for i in sim.active_echoes():
			var rec := sim.echoes[i]
			var p := rec.position_at(t)
			var c := rec.hue()
			entities.draw_circle(p, 11.0, Color(c, ECHO_ALPHA * 0.35))
			entities.draw_circle(p, 7.5, Color(c, ECHO_ALPHA))
			entities.draw_circle(p, 3.5, Color(1, 1, 1, ECHO_ALPHA + 0.15))

	if sim.alive:
		var p := _player_draw_pos()
		var f := clampf(sim.flame / sim.max_flame, 0.0, 1.0)
		entities.draw_circle(p, Tuning.PLAYER_RADIUS, Color(PLAYER_COLOR, 1.0))
		# The white core shrinks as the flame runs low.
		entities.draw_circle(p, Tuning.PLAYER_RADIUS * lerpf(0.2, 0.5, f), Color(1.0, 0.97, 0.88))
		entities.draw_arc(p, Tuning.PLAYER_RADIUS + 2.5, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 1.5, true)
		if state == State.PLAYING and _autopilot == null and _mouse_steer:
			# Where the mouse is steering the lantern.
			entities.draw_arc(get_global_mouse_position(), 5.0, 0.0, TAU, 16, Color(1, 1, 1, 0.35), 1.0, true)


func _draw_rim(s: NightSim.Shadow, pos: Vector2, r: float) -> void:
	if s.burning < 0.12:
		var heat := 0.5 + 0.5 * sin(_render_time * 40.0 + s.phase)
		entities.draw_arc(pos, r, 0.0, TAU, 20, Color(BURN_RIM, 0.45 + 0.4 * heat), 2.0, true)


## End of run: every Echo's whole route, faint, under the run just finished in gold.
func _draw_develop() -> void:
	if not overlay.visible:
		return
	for rec in sim.echoes:
		var path := rec.path_between(0.0, rec.duration)
		if path.size() >= 2:
			var hl := rec == _highlight
			develop.draw_polyline(path, Color(rec.hue(), 0.55 if hl else 0.1), 3.0 if hl else 1.5, hl)
	var whole := sim.recording.path_between(0.0, sim.recording.duration)
	var a := 0.85 if _highlight == null or _highlight == sim.recording else 0.25
	if whole.size() >= 2:
		develop.draw_polyline(whole, Color(PLAYER_COLOR, a), 2.5, true)


func _draw_flame_bar() -> void:
	var size := flame_bar.size
	var f := clampf(sim.flame / sim.max_flame, 0.0, 1.0)
	flame_bar.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.18))
	var low := f < 0.3 and int(_render_time * 4.0) % 2 == 0
	flame_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * f, size.y)), Color(1.0, 0.35, 0.2) if low else PLAYER_COLOR)
	flame_bar.draw_rect(Rect2(Vector2.ZERO, size).grow(1.0), Color(0, 0, 0, 0.6), false, 1.0)
	# Embers toward the next level, as a thin line under the flame.
	var e := clampf(float(sim.embers) / sim.embers_for_next_level(), 0.0, 1.0)
	flame_bar.draw_rect(Rect2(Vector2(0, size.y + 3.0), Vector2(size.x, 2.0)), Color(1, 1, 1, 0.12))
	flame_bar.draw_rect(Rect2(Vector2(0, size.y + 3.0), Vector2(size.x * e, 2.0)), Color(1.0, 0.86, 0.55, 0.9))


## HUD labels fade when the lantern passes under them, so neither hides the other.
func _fade_hud_near_lantern() -> void:
	var p := _player_draw_pos()
	for c in hud_top:
		var near := c.get_global_rect().grow(40.0).has_point(p)
		c.modulate.a = move_toward(c.modulate.a, 0.35 if near else 1.0, 0.08)


func _update_hud() -> void:
	clock_label.text = NightClock.label(sim.t)
	var lit := sim.active_echoes().size()
	if sim.echoes.is_empty():
		run_label.text = "Run %d    no Echoes yet" % GameState.run_number
	else:
		run_label.text = "Run %d    %d of %d Echoes lit" % [GameState.run_number, lit, sim.echoes.size()]
	burned_label.text = "Lv %d    %d burned" % [sim.level, sim.burned]
