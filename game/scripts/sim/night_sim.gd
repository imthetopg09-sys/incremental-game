class_name NightSim
extends RefCounted
## The whole night as plain logic: the lantern, the shadows, the Echoes and the light.
## No nodes, so tests and balance bots can run thousands of nights headless.
## Call step() at a fixed rate; read `events` after each step for effects.

class Shadow:
	var kind: String
	var pos: Vector2
	var hp: float
	var max_hp: float
	var radius: float
	var speed: float
	var contact_dps: float
	var phase: float  # wobble / flank side seed
	var burning := 0.0  # seconds since last burned, for visuals
	var facing := Vector2.DOWN

	func _init(k: String, p: Vector2, ph: float) -> void:
		kind = k
		pos = p
		phase = ph
		var s: Dictionary = Tuning.SHADOWS[k]
		hp = s["hp"]
		max_hp = hp
		radius = s["radius"]
		speed = s["speed"]
		contact_dps = s["contact_dps"]
		burning = 99.0


var arena := Rect2(Vector2.ZERO, Tuning.ARENA_SIZE)
var t := 0.0
var player_pos: Vector2
var flame := Tuning.PLAYER_MAX_FLAME
var max_flame := Tuning.PLAYER_MAX_FLAME
var alive := true
var reached_dawn := false
var shadows: Array[Shadow] = []
var echoes: Array[EchoRecording] = []
var recording := EchoRecording.new()
var burned := 0
var burned_by_echoes := 0
## Effects from the last step: {type: "burn", pos, kind, light} where light is -1 for
## the player or the index into `echoes`; {type: "split", pos}; {type: "hour", hour};
## {type: "death", pos}; {type: "dawn"}.
var events: Array[Dictionary] = []

var _schedule: SpawnSchedule
var _spawn_count := 0
var _lights: Array[Vector4] = []  # x, y, radius, dps


func _init(echo_list: Array[EchoRecording] = [], seed_value: int = Tuning.NIGHT_SEED, run_number: int = 1) -> void:
	echoes = echo_list
	_schedule = SpawnSchedule.new(seed_value, arena)
	player_pos = arena.get_center()
	recording.run_number = run_number
	recording.record_until(0.0, player_pos)


func is_over() -> bool:
	return not alive or reached_dawn


func light_radius() -> float:
	var f := clampf(flame / max_flame, 0.0, 1.0)
	return Tuning.PLAYER_LIGHT_RADIUS * lerpf(Tuning.LIGHT_AT_EMPTY_FLAME, 1.0, f)


func active_echoes() -> Array[int]:
	var out: Array[int] = []
	for i in echoes.size():
		if echoes[i].is_active(t):
			out.append(i)
	return out


## Advances the night by dt seconds with the lantern steering toward `target`.
func step(dt: float, target: Vector2) -> void:
	events.clear()
	if is_over():
		return
	var prev_hour := NightClock.hour_index(t)
	t += dt
	var hour := NightClock.hour_index(t)
	if hour != prev_hour and hour < Tuning.NIGHT_HOURS:
		events.append({"type": "hour", "hour": hour})

	_move_player(dt, target)
	recording.record_until(t, player_pos)
	for s in _schedule.due(t):
		_spawn(s["kind"], s["pos"])
	_move_shadows(dt)
	_burn(dt)
	_contact(dt)

	if flame <= 0.0:
		flame = 0.0
		alive = false
		_finish(true)
		events.append({"type": "death", "pos": player_pos})
	elif t >= Tuning.NIGHT_LENGTH:
		reached_dawn = true
		_finish(false)
		events.append({"type": "dawn"})


func _finish(died: bool) -> void:
	recording.burned = burned
	recording.finish(t, player_pos, died)


func _move_player(dt: float, target: Vector2) -> void:
	var to := target - player_pos
	var max_step := Tuning.PLAYER_SPEED * dt
	player_pos += to if to.length() <= max_step else to.normalized() * max_step
	var m := Tuning.PLAYER_RADIUS
	player_pos = player_pos.clamp(arena.position + Vector2(m, m), arena.end - Vector2(m, m))


func _spawn(kind: String, pos: Vector2) -> void:
	_spawn_count += 1
	# Golden-ratio phase keeps wobble and flank sides varied but deterministic.
	shadows.append(Shadow.new(kind, pos, fmod(_spawn_count * 0.618034, 1.0) * TAU))


func _move_shadows(dt: float) -> void:
	for s in shadows:
		var to_player := player_pos - s.pos
		var dist := to_player.length()
		var dir := to_player / dist if dist > 0.001 else Vector2.ZERO
		var target_dir := dir
		match s.kind:
			"wisp":
				var wobble := sin(t * 1.7 + s.phase) * 0.45
				target_dir = (dir + dir.orthogonal() * wobble).normalized()
			"creeper":
				# Flankers circle toward your side, then cut straight in.
				if dist > 140.0:
					var side := 1.0 if sin(s.phase) >= 0.0 else -1.0
					target_dir = (dir + dir.orthogonal() * side * 0.9).normalized()
		if target_dir != Vector2.ZERO:
			s.facing = target_dir
		s.pos += target_dir * s.speed * dt
		s.burning += dt
	_separate()


## Pushes overlapping shadows apart using a coarse grid so crowds stay readable.
func _separate() -> void:
	var cell := 48.0
	var grid := {}
	for i in shadows.size():
		var key := Vector2i((shadows[i].pos / cell).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	for i in shadows.size():
		var a := shadows[i]
		var key := Vector2i((a.pos / cell).floor())
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var bucket = grid.get(key + Vector2i(dx, dy))
				if bucket == null:
					continue
				for j in bucket:
					if j <= i:
						continue
					var b := shadows[j]
					var d := b.pos - a.pos
					var min_d := (a.radius + b.radius) * 0.9
					var len := d.length()
					if len < min_d and len > 0.001:
						var push := d / len * (min_d - len) * 0.5
						a.pos -= push
						b.pos += push


func _burn(dt: float) -> void:
	_lights.clear()
	_lights.append(Vector4(player_pos.x, player_pos.y, light_radius(), Tuning.PLAYER_BURN_DPS))
	var echo_index: Array[int] = [-1]
	for i in active_echoes():
		var p := echoes[i].position_at(t)
		_lights.append(Vector4(p.x, p.y, Tuning.ECHO_LIGHT_RADIUS, Tuning.ECHO_BURN_DPS))
		echo_index.append(i)

	var dead: Array[int] = []
	for si in shadows.size():
		var s := shadows[si]
		var killer := -2
		for li in _lights.size():
			var L := _lights[li]
			var reach := L.z + s.radius * 0.5
			var d := s.pos.distance_to(Vector2(L.x, L.y))
			if d < reach:
				s.hp -= L.w * lerpf(1.0, Tuning.BURN_EDGE_FACTOR, d / reach) * dt
				s.burning = 0.0
				if s.hp <= 0.0 and killer == -2:
					killer = echo_index[li]
		if s.hp <= 0.0:
			dead.append(si)
			burned += 1
			if killer >= 0:
				burned_by_echoes += 1
			events.append({"type": "burn", "pos": s.pos, "kind": s.kind, "light": killer})

	for k in range(dead.size() - 1, -1, -1):
		var s: Shadow = shadows[dead[k]]
		shadows.remove_at(dead[k])
		if s.kind == "bloat":
			events.append({"type": "split", "pos": s.pos})
			for n in Tuning.BLOAT_SPLIT:
				var off := Vector2.from_angle(TAU * n / Tuning.BLOAT_SPLIT + s.phase) * s.radius
				_spawn("mite", s.pos + off)


func _contact(dt: float) -> void:
	for s in shadows:
		if s.pos.distance_to(player_pos) < Tuning.PLAYER_RADIUS + s.radius:
			flame -= s.contact_dps * dt
