extends Control
## The Lamp Tree, shown between nights: spend Tallow on the tree, braid kept Echoes
## into Choruses, then light the next night.
##
## Assumes GameState.run_number is already the coming night (the night calls
## begin_next_run before it leaves). Dev flags (after `--`): --demo-tree fills the
## Sconces with bot runs and gives 400 Tallow; --demo-chorus also braids two of
## them and buys a few nodes, for screenshots.

const PLAYER_COLOR := Color(1.0, 0.72, 0.36)
const TEXT := Color(0.92, 0.86, 0.76)
const MUTED := Color(0.85, 0.78, 0.68, 0.6)
const DENIED := Color(1.0, 0.48, 0.38)
const CARD_BG := Color(0.04, 0.034, 0.042, 0.94)
const CARD_DIM := Color(0.55, 0.55, 0.58)
const SLOT_BG := Color(0.02, 0.018, 0.026, 0.9)
const PIP_SIZE := 11.0
const PIP_GAP := 7.0
const CARD_SIZE := Vector2(289, 137)
const SLOT_WIDTH := 156.0
const THUMB_SIZE := Vector2(140, 79)
## How many path points a thumbnail draws per run, at most.
const THUMB_POINTS := 400
const PULSE_TIME := 0.45
const LIGHT_RADIUS := 240.0
const STRIKE_RADIUS := 420.0
const LIGHT_FOLLOW := 10.0
const NIGHT_SCENE := "res://scenes/night.tscn"
const TITLE_SCENE := "res://scenes/main.tscn"
const DAY_TOWN_SCENE := "res://scenes/day_town.tscn"

@onready var night: ColorRect = $Night
@onready var tallow_label: Label = %Tallow
@onready var info_label: Label = %Info
@onready var grid: GridContainer = %Grid
@onready var sconce_count: Label = %SconceCount
@onready var braid_hint: Label = %BraidHint
@onready var slots_box: HBoxContainer = %Slots
@onready var tonight_label: Label = %Tonight
@onready var stats_label: Label = %Stats
@onready var light_button: Button = %Light

## The Echo picked as the first half of a braid, or null.
var selected: EchoRecording = null
var _hovered: EchoRecording = null
var _hover_card := ""
## Node id -> {"panel", "name", "pips", "cost"}.
var _cards := {}
## One per Sconce: {"panel", "rec" (null when hollow), "extra", "locked"}.
var _slots: Array[Dictionary] = []
## Node id or Echo -> seconds of highlight left after a buy or braid.
var _pulse := {}
var _light_pos := Vector2.ZERO
var _radius := LIGHT_RADIUS
var _leaving := false
## Clicks and keys are ignored this long after the screen opens, so the rest of a
## double click on the end screen cannot buy a node or skip the tree.
var input_delay := 0.35
var _opened_at := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--demo-tree") or args.has("--demo-chorus"):
		GameState.autosave = false
		GameState.make_demo_echoes(3)
		GameState.tallow = 400
		for e in GameState.echoes:
			GameState.best_time = maxf(GameState.best_time, e.duration)
		if args.has("--demo-chorus"):
			GameState.braid(GameState.echoes[0], GameState.echoes[1])
			for id in ["thick_wick", "thick_wick", "foresight", "wide_glow"]:
				GameState.buy(id)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_opened_at = Time.get_ticks_msec() / 1000.0
	light_button.pressed.connect(func():
		if _settled():
			light_next_night())
	_light_pos = Vector2(size.x * 0.5, 60.0)
	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("light_count", 1)
	mat.set_shader_parameter("light_colors", PackedVector4Array([Vector4(PLAYER_COLOR.r, PLAYER_COLOR.g, PLAYER_COLOR.b, 1.0)]))
	_build_cards()
	_build_slots()
	if GameState.daylight > 0:
		_build_day_town_link()
	_refresh()


func _process(delta: float) -> void:
	var target := get_local_mouse_position()
	if not Rect2(Vector2.ZERO, size).has_point(target):
		target = Vector2(size.x * 0.5, 60.0)
	_light_pos = _light_pos.lerp(target, 1.0 - exp(-LIGHT_FOLLOW * delta))
	if not _leaving:
		_radius = lerpf(_radius, LIGHT_RADIUS, 1.0 - exp(-3.0 * delta))
	var flicker := 0.95 + 0.03 * sin(Time.get_ticks_msec() * 0.013)
	var mat := night.material as ShaderMaterial
	mat.set_shader_parameter("lights", PackedVector4Array([Vector4(_light_pos.x, _light_pos.y, _radius * flicker, 0.7)]))
	mat.set_shader_parameter("rect_size", night.size)
	if not _pulse.is_empty():
		for key in _pulse.keys():
			_pulse[key] -= delta
			if _pulse[key] <= 0.0:
				_pulse.erase(key)
		_style_cards()
		_style_slots()


# --- Actions ------------------------------------------------------------------

## Buys the next level of a Lamp Tree node. Returns false when it is maxed or too dear.
func try_buy(id: String) -> bool:
	var cost := Upgrades.next_cost(id, GameState.level(id))
	if not GameState.buy(id):
		_deny(_cards[id]["cost"] if _cards.has(id) else null, cost >= 0)
		return false
	GameState.save()
	_pulse[id] = PULSE_TIME
	_bump(_cards[id]["panel"] if _cards.has(id) else null)
	_spent(cost)
	_sfx("level_up")
	if id == "extra_sconce":
		_build_slots()
	_refresh()
	return true


## Picks `rec` as the first half of a braid, braids it into the one already picked,
## or deselects it when it is picked twice. Returns true when a braid happened.
func click_echo(rec: EchoRecording) -> bool:
	if selected == null:
		selected = rec
		_sfx("ui_click")
	elif selected == rec:
		selected = null
	else:
		var into := selected
		var cost := GameState.braid_cost(into, rec)
		if not GameState.braid(into, rec):
			_deny(braid_hint, GameState.tallow < cost)
			_refresh()
			return false
		GameState.save()
		selected = null
		_hovered = null
		_build_slots()
		_pulse[into] = PULSE_TIME
		for s in _slots:
			if s["rec"] == into:
				_bump(s["panel"])
		_spent(cost)
		_sfx("level_up")
		_refresh()
		return true
	_refresh()
	return false


func deselect() -> void:
	selected = null
	_refresh()


func light_next_night() -> void:
	if _leaving:
		return
	_leaving = true
	GameState.save()
	_radius = STRIKE_RADIUS
	_sfx("strike")
	await get_tree().create_timer(0.3).timeout
	get_tree().change_scene_to_file(NIGHT_SCENE)


func go_to_title() -> void:
	if _leaving:
		return
	_leaving = true
	GameState.save()
	get_tree().change_scene_to_file(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving:
		return
	if event.is_action_pressed("ui_accept") and _settled():
		get_viewport().set_input_as_handled()
		light_next_night()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if selected != null:
			deselect()
		else:
			go_to_title()


## A click on empty space drops the braid pick.
func _gui_input(event: InputEvent) -> void:
	if _is_click(event) and selected != null:
		deselect()


func _is_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _settled()


func _settled() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _opened_at >= input_delay


func _sfx(sound: String) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method(sound):
		sfx.call(sound)


# --- Feedback -------------------------------------------------------------------

## A quick scale pop on a card or slot.
func _bump(c: Control) -> void:
	if c == null:
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(1.06, 1.06)
	create_tween().tween_property(c, "scale", Vector2.ONE, PULSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Flashes a label red for a click that did nothing, and the Tallow count too when
## Tallow was what was missing.
func _deny(label: Label, short_of_tallow: bool) -> void:
	_sfx("ui_click")
	for l in [label, tallow_label if short_of_tallow else null]:
		if l == null:
			continue
		l.self_modulate = DENIED * 1.4
		create_tween().tween_property(l, "self_modulate", Color.WHITE, 0.5)


## A "-45" that drifts down from the Tallow count and fades.
func _spent(amount: int) -> void:
	var l := _label("-%d" % amount, 26, PLAYER_COLOR)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.size = Vector2(120, 36)
	var font := tallow_label.get_theme_font("font")
	var font_size := tallow_label.get_theme_font_size("font_size")
	var text_w := font.get_string_size(tallow_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var right := tallow_label.position.x + tallow_label.size.x - text_w - 16.0
	l.position = Vector2(right - l.size.x, tallow_label.position.y + (tallow_label.size.y - l.size.y) * 0.5)
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y + 24, 0.8).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tw.chain().tween_callback(l.queue_free)
	tallow_label.pivot_offset = tallow_label.size * Vector2(1.0, 0.5)
	tallow_label.scale = Vector2(1.08, 1.08)
	create_tween().tween_property(tallow_label, "scale", Vector2.ONE, 0.3)


# --- Building -------------------------------------------------------------------

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _box(bg: Color, border: Color, width := 2, margin := 14.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(10)
	box.set_content_margin_all(margin)
	box.content_margin_left = margin + 2.0
	box.content_margin_right = margin + 2.0
	return box


func _build_cards() -> void:
	for n in Upgrades.TREE:
		var id: String = n["id"]
		var panel := PanelContainer.new()
		panel.custom_minimum_size = CARD_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 2)
		panel.add_child(box)
		var name_label := _label(n["name"], 21, PLAYER_COLOR.lightened(0.25))
		box.add_child(name_label)
		var desc := _label(n["desc"], 15, Color(TEXT, 0.85))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(desc)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var pips := Control.new()
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.custom_minimum_size = Vector2(Upgrades.max_level(id) * (PIP_SIZE + PIP_GAP), 24)
		pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pips.draw.connect(_draw_pips.bind(pips, id))
		row.add_child(pips)
		var cost := _label("", 18, PLAYER_COLOR)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cost)
		panel.gui_input.connect(func(event: InputEvent):
			if _is_click(event):
				panel.accept_event()
				try_buy(id))
		panel.mouse_entered.connect(func():
			_hover_card = id
			_style_cards())
		panel.mouse_exited.connect(func():
			if _hover_card == id:
				_hover_card = ""
				_style_cards())
		grid.add_child(panel)
		_cards[id] = {"panel": panel, "name": name_label, "pips": pips, "cost": cost}


## One slot per Sconce, kept Echoes first, then hollow ones, then the Sconces the
## tree can still grow.
func _build_slots() -> void:
	for c in slots_box.get_children():
		slots_box.remove_child(c)
		c.queue_free()
	_slots.clear()
	var owned := maxi(GameState.sconces, GameState.echoes.size())
	var most := maxi(owned, Tuning.START_SCONCES + Upgrades.max_level("extra_sconce"))
	for i in most:
		var rec: EchoRecording = GameState.echoes[i] if i < GameState.echoes.size() else null
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(SLOT_WIDTH, 0)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_theme_constant_override("separation", 1)
		panel.add_child(box)
		var thumb := Control.new()
		thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		thumb.custom_minimum_size = THUMB_SIZE
		box.add_child(thumb)
		var slot := {"panel": panel, "rec": rec, "extra": null, "locked": i >= owned}
		if rec == null:
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var locked: bool = slot["locked"]
			var empty := _label("Locked" if locked else "Empty Sconce", 15, Color(MUTED, 0.55 if locked else 0.6))
			empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
			empty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if locked else VERTICAL_ALIGNMENT_CENTER
			box.add_child(empty)
			if locked:
				var how := _label("Grow Extra Sconce", 13, Color(MUTED, 0.55))
				how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				how.size_flags_vertical = Control.SIZE_EXPAND_FILL
				box.add_child(how)
			thumb.draw.connect(_draw_empty_thumb.bind(thumb, locked))
		else:
			panel.mouse_filter = Control.MOUSE_FILTER_STOP
			panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			thumb.draw.connect(_draw_thumb.bind(thumb, rec))
			box.add_child(_label("Run %d" % rec.run_number, 17, rec.hue()))
			var reach := NightClock.label(rec.duration) if rec.died else "dawn"
			box.add_child(_label("held until %s" % reach, 14, Color(TEXT, 0.85)))
			var extra := _label("", 14, MUTED)
			box.add_child(extra)
			slot["extra"] = extra
			panel.gui_input.connect(func(event: InputEvent):
				if _is_click(event):
					panel.accept_event()
					click_echo(rec))
			panel.mouse_entered.connect(func():
				_hovered = rec
				_refresh_braid())
			panel.mouse_exited.connect(func():
				if _hovered == rec:
					_hovered = null
					_refresh_braid())
		slots_box.add_child(panel)
		_slots.append(slot)


## After the first Dawn, a way back to the Day Town under the Tallow count.
func _build_day_town_link() -> void:
	var b := Button.new()
	b.flat = true
	b.text = "Visit the Day Town"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", PLAYER_COLOR)
	b.add_theme_color_override("font_pressed_color", PLAYER_COLOR)
	b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -240.0
	b.offset_right = -36.0
	b.offset_top = 74.0
	b.offset_bottom = 102.0
	b.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.pressed.connect(func():
		if _leaving:
			return
		_leaving = true
		_sfx("ui_click")
		GameState.save()
		get_tree().change_scene_to_file(DAY_TOWN_SCENE))
	add_child(b)


# --- Refreshing -----------------------------------------------------------------

func _refresh() -> void:
	tallow_label.text = "%d Tallow" % GameState.tallow
	var info := "Run %d next" % GameState.run_number
	if GameState.best_time >= Tuning.NIGHT_LENGTH:
		info += "      Best night reached dawn"
	elif GameState.best_time > 0.0:
		info += "      Best night reached %s" % NightClock.label(GameState.best_time)
	if GameState.daylight > 0:
		info += "      %d Daylight" % GameState.daylight
	info_label.text = info
	_style_cards()
	sconce_count.text = "%d of %d filled" % [GameState.echoes.size(), GameState.sconces]
	var runs := 0
	for e in GameState.echoes:
		runs += e.members().size()
	if runs == 0:
		tonight_label.text = "You walk alone."
	else:
		tonight_label.text = "%d %s with you." % [runs, "run walks" if runs == 1 else "runs walk"]
	stats_label.text = _stats_text(GameState.stats())
	_refresh_braid()


## What the tree has changed about the night, one item per stat that grew.
## Items are joined with no-break spaces inside so a wrap never splits one.
func _stats_text(st: Dictionary) -> String:
	var items: Array[String] = []
	var pct := func(key: String, what: String) -> void:
		var bonus := roundi((float(st[key]) - 1.0) * 100.0)
		if bonus > 0:
			items.append("%s +%d%%" % [what, bonus])
	pct.call("flame_mult", "Flame")
	pct.call("radius_mult", "Light")
	pct.call("burn_mult", "Burn")
	pct.call("tallow_mult", "Tallow")
	if float(st["foresight"]) > Tuning.FORESIGHT_SECONDS:
		items.append("Foresight %s s" % str(snappedf(float(st["foresight"]), 0.1)))
	if float(st["afterglow"]) > 0.0:
		items.append("Afterglow %d s" % int(st["afterglow"]))
	if int(st["kindling"]) > 0:
		items.append("%d %s at dusk" % [int(st["kindling"]), "Boon" if int(st["kindling"]) == 1 else "Boons"])
	if items.is_empty():
		return "The lantern burns as it always has."
	return "   ".join(PackedStringArray(items.map(func(i: String) -> String: return i.replace(" ", "\u00a0"))))


func _refresh_braid() -> void:
	_style_slots()
	var hint := _braid_hint()
	braid_hint.text = hint[0]
	braid_hint.add_theme_color_override("font_color", hint[1])


## The hint line under "Sconces" and its color, for the current pick and hover.
func _braid_hint() -> Array:
	if selected == null:
		if _hovered != null and GameState.echoes.size() < 2:
			return ["Keep a second Echo to braid it with Run %d into one Sconce." % _hovered.run_number, MUTED]
		if _hovered != null:
			if _hovered.members().size() >= GameState.CHORUS_MAX:
				return ["Run %d is a full Chorus: %d runs is the most one Sconce holds." % [_hovered.run_number, GameState.CHORUS_MAX], MUTED]
			return ["Click to pick Run %d, then click another Echo to braid it in for %d Tallow." % [_hovered.run_number, GameState.braid_cost(_hovered)], Color(_hovered.hue(), 0.9)]
		if GameState.echoes.size() < 2:
			return ["Keep two Echoes to braid them into one Sconce (both still walk).", MUTED]
		return ["Braid two Echoes into one Sconce (both still walk). Click one, then another.", MUTED]
	var cost := GameState.braid_cost(selected)
	if _hovered != null and _hovered != selected:
		cost = GameState.braid_cost(selected, _hovered)
		if GameState.can_braid(selected, _hovered):
			return ["Click to braid Run %d into Run %d for %d Tallow." % [_hovered.run_number, selected.run_number, cost], Color(selected.hue(), 0.95)]
		if selected.members().size() + _hovered.members().size() > GameState.CHORUS_MAX:
			return ["Too many runs: a Chorus holds at most %d." % GameState.CHORUS_MAX, DENIED]
		return ["Braiding into Run %d costs %d Tallow. You have %d." % [selected.run_number, cost, GameState.tallow], DENIED]
	return ["Run %d picked. Braiding costs %d Tallow: click another Echo, or Run %d again to cancel." % [selected.run_number, cost, selected.run_number], Color(selected.hue(), 0.95)]


func _style_cards() -> void:
	for id in _cards:
		var card: Dictionary = _cards[id]
		var panel: PanelContainer = card["panel"]
		var cost := Upgrades.next_cost(id, GameState.level(id))
		var maxed := cost < 0
		var affordable := GameState.can_buy(id)
		var hover: bool = _hover_card == id
		var pulse := clampf(_pulse.get(id, 0.0) / PULSE_TIME, 0.0, 1.0)
		var bg := CARD_BG
		var border := Color(1, 1, 1, 0.08)
		if maxed:
			border = Color(PLAYER_COLOR, 0.22)
		elif affordable:
			border = Color(PLAYER_COLOR, 0.95 if hover else 0.4)
			if hover:
				bg = CARD_BG.lerp(Color(PLAYER_COLOR, 1.0), 0.08)
		elif hover:
			border = Color(1, 1, 1, 0.22)
		bg = bg.lerp(Color(PLAYER_COLOR, 1.0), 0.3 * pulse)
		border = border.lerp(Color(1.0, 0.9, 0.7, 1.0), pulse)
		panel.add_theme_stylebox_override("panel", _box(bg, border))
		panel.modulate = Color.WHITE if affordable or maxed or pulse > 0.0 else (CARD_DIM.lightened(0.15) if hover else CARD_DIM)
		panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if affordable else Control.CURSOR_ARROW
		var cost_label: Label = card["cost"]
		cost_label.text = "Max" if maxed else "%d Tallow" % cost
		cost_label.add_theme_color_override("font_color", Color(PLAYER_COLOR, 0.6) if maxed else (PLAYER_COLOR if affordable else MUTED))
		(card["pips"] as Control).queue_redraw()


func _style_slots() -> void:
	for s in _slots:
		var panel: PanelContainer = s["panel"]
		var rec: EchoRecording = s["rec"]
		if rec == null:
			var locked: bool = s["locked"]
			var hollow := _box(Color(0, 0, 0, 0), Color(1, 1, 1, 0.05 if locked else 0.12), 1 if locked else 2, 8.0)
			hollow.content_margin_left = 8.0
			hollow.content_margin_right = 8.0
			panel.add_theme_stylebox_override("panel", hollow)
			continue
		var hue := rec.hue()
		var pulse := clampf(_pulse.get(rec, 0.0) / PULSE_TIME, 0.0, 1.0)
		var bg := SLOT_BG.lerp(Color(hue, 1.0), 0.05)
		var border := Color(hue, 0.3)
		var width := 2
		var extra: Label = s["extra"]
		if rec.chorus.is_empty():
			extra.text = "%d burned" % rec.burned
			extra.add_theme_color_override("font_color", MUTED)
		else:
			extra.text = "Chorus of %d runs" % rec.members().size()
			extra.add_theme_color_override("font_color", Color(hue, 0.85))
		if rec == selected:
			border = hue
			width = 3
			bg = SLOT_BG.lerp(Color(hue, 1.0), 0.14)
			extra.text = "Braid: %d Tallow" % GameState.braid_cost(rec)
			extra.add_theme_color_override("font_color", hue)
		elif rec == _hovered:
			if selected == null:
				border = Color(hue, 0.75)
			elif GameState.can_braid(selected, rec):
				border = Color(selected.hue(), 0.9)
				bg = SLOT_BG.lerp(Color(selected.hue(), 1.0), 0.1)
			else:
				border = Color(DENIED, 0.6)
		bg = bg.lerp(Color(hue, 1.0), 0.3 * pulse)
		border = border.lerp(Color.WHITE, pulse)
		var box := _box(bg, border, width, 8.0)
		box.content_margin_left = 8.0
		box.content_margin_right = 8.0
		panel.add_theme_stylebox_override("panel", box)


# --- Drawing --------------------------------------------------------------------

## Filled pips for levels bought, hollow ones for the rest.
func _draw_pips(c: Control, id: String) -> void:
	var lv := GameState.level(id)
	var r := PIP_SIZE * 0.5
	for i in Upgrades.max_level(id):
		var center := Vector2(r + 1.0 + i * (PIP_SIZE + PIP_GAP), c.size.y * 0.5)
		if i < lv:
			c.draw_circle(center, r, PLAYER_COLOR)
			c.draw_circle(center, r * 0.4, Color(1.0, 0.95, 0.85, 0.9))
		else:
			c.draw_arc(center, r - 0.75, 0.0, TAU, 20, Color(PLAYER_COLOR, 0.45), 1.5, true)


## The Echo's whole route across the night, scaled down, in its hue. A Chorus draws
## every braided run.
func _draw_thumb(c: Control, rec: EchoRecording) -> void:
	var rect := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(rect, Color(0, 0, 0, 0.6))
	var k := minf(rect.size.x / Tuning.ARENA_SIZE.x, rect.size.y / Tuning.ARENA_SIZE.y)
	var offset := (rect.size - Tuning.ARENA_SIZE * k) * 0.5
	var hue := rec.hue()
	for m in rec.members():
		var n := m.points.size()
		if n == 0:
			continue
		var pts := PackedVector2Array()
		var step := maxi(1, n / THUMB_POINTS)
		for i in range(0, n, step):
			pts.append(offset + m.points[i] * k)
		var end := offset + m.points[n - 1] * k
		pts.append(end)
		if pts.size() >= 2:
			c.draw_polyline(pts, Color(hue, 0.85 if m == rec else 0.55), 1.2, true)
		if m.died:
			c.draw_arc(end, 3.0, 0.0, TAU, 12, Color(hue, 0.95), 1.2, true)
		else:
			c.draw_circle(end, 2.5, Color(1.0, 0.97, 0.88))
	c.draw_rect(rect, Color(hue, 0.18), false, 1.0)


## A hollow Sconce: an unlit ring. A locked one is fainter still.
func _draw_empty_thumb(c: Control, locked: bool) -> void:
	var a := 0.5 if locked else 1.0
	var rect := Rect2(Vector2.ZERO, c.size).grow(-1.0)
	c.draw_rect(rect, Color(1, 1, 1, 0.07 * a), false, 1.0)
	c.draw_arc(rect.get_center(), 11.0, 0.0, TAU, 24, Color(PLAYER_COLOR, 0.25 * a), 1.5, true)
