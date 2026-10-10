class_name NightSim
extends RefCounted
## The whole night as plain logic: the lantern, the shadows, the Echoes, the light
## and the Boons. No nodes, so tests and balance bots can run thousands of nights
## headless. Call step() at a fixed rate; read `events` after each step for effects.
##
## Level-ups: when `pending_level_ups` > 0 the caller should offer `offer()` and call
## pick_boon(). The scene pauses the night while the player chooses; bots pick at once.

class Shadow:
	var kind: String
	var pos: Vector2
	var prev_pos: Vector2  # position before the last step, for smooth drawing
	var hp: float
	var max_hp: float
	var radius: float
	var speed: float
	var contact_dps: float
	var phase: float  # wobble / flank side seed
	var burning := 0.0  # seconds since last burned, for visuals
	var facing := Vector2.DOWN
	var killer := -2  # light that dealt the killing blow: -1 player, >= 0 echo index

	func _init(k: String, p: Vector2, ph: float) -> void:
		kind = k
		pos = p
		prev_pos = p
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
var prev_player_pos: Vector2
var stats: Dictionary
var flame := Tuning.PLAYER_MAX_FLAME
var max_flame := Tuning.PLAYER_MAX_FLAME
var alive := true
var reached_dawn := false
var shadows: Array[Shadow] = []
var echoes: Array[EchoRecording] = []
var recording := EchoRecording.new()
var burned := 0
var burned_by_echoes := 0
var burned_by_kind := {}

# Embers and Boons.
var embers := 0
var level := 1
var pending_level_ups := 0
var boons := {}  # the living lantern's Boon levels

## Everything that carries light and Boons this step: the lantern, then each walking
## Echo. {pos, boons, light} where light is -1 for the lantern or the echo index.
var casters: Array[Dictionary] = []
## Homing Flare bolts: {pos, prev_pos, target: Shadow, dmg, light, age}.
var bolts: Array[Dictionary] = []
## Candle wax pools: {pos, age, life, dps, light}.
var wax: Array[Dictionary] = []

## Effects from the last step: {type: "burn", pos, kind, light} where light is -1 for
## the player or the index into `echoes`; {type: "split", pos}; {type: "hour", hour};
## {type: "level_up", level}; {type: "spark", points, light}; {type: "flare", light};
## {type: "death", pos}; {type: "dawn"}.
var events: Array[Dictionary] = []

var _schedule: SpawnSchedule
var _spawn_count := 0
var _rng := RandomNumberGenerator.new()
var _timers := {}  # caster light -> {flare, candle, spark, last_drop}
var _ember_frac := 0.0


func _init(echo_list: Array[EchoRecording] = [], seed_value: int = Tuning.NIGHT_SEED, run_number: int = 1, stats_in: Dictionary = {}) -> void:
	echoes = echo_list
	stats = stats_in if not stats_in.is_empty() else Upgrades.stats({})
	max_flame = Tuning.PLAYER_MAX_FLAME * stats["flame_mult"]
	flame = max_flame
	_schedule = SpawnSchedule.new(seed_value, arena)
	_rng.seed = hash([seed_value, run_number])
	player_pos = arena.get_center()
	prev_player_pos = player_pos
	recording.run_number = run_number
	recording.record_until(0.0, player_pos)
	pending_level_ups = mini(stats["kindling"], _room_for_picks())
	_refresh_casters()


func is_over() -> bool:
	return not alive or reached_dawn


func light_radius() -> float:
	var f := clampf(flame / max_flame, 0.0, 1.0)
	return Tuning.PLAYER_LIGHT_RADIUS * stats["radius_mult"] * lerpf(Tuning.LIGHT_AT_EMPTY_FLAME, 1.0, f)


func echo_light_radius() -> float:
	return Tuning.ECHO_LIGHT_RADIUS * stats["radius_mult"]


func active_echoes() -> Array[int]:
	var out: Array[int] = []
	for i in echoes.size():
		if echoes[i].is_active(t):
			out.append(i)
	return out


## Spent Echoes still glowing in place thanks to Afterglow.
func glowing_echoes() -> Array[int]:
	var out: Array[int] = []
	var glow: float = stats["afterglow"]
	if glow <= 0.0:
		return out
	for i in echoes.size():
		var rec := echoes[i]
		if t > rec.duration and t - rec.duration <= glow:
			out.append(i)
	return out


func embers_for_next_level() -> int:
	var n := level - 1
	return Tuning.LEVEL_BASE + Tuning.LEVEL_STEP * n + Tuning.LEVEL_CURVE * n * n


## Up to three Boons to choose from for the next level-up.
func offer() -> Array[String]:
	var pool: Array[String] = []
	for b in Upgrades.BOONS:
		if boons.get(b["id"], 0) < Upgrades.BOON_MAX_LEVEL:
			pool.append(b["id"])
	# Fisher-Yates with the night's own RNG so offers do not depend on frame timing.
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, 3)


func pick_boon(id: String) -> void:
	if pending_level_ups <= 0 or Upgrades.boon(id).is_empty() or boons.get(id, 0) >= Upgrades.BOON_MAX_LEVEL:
		return
	pending_level_ups -= 1
	boons[id] = boons.get(id, 0) + 1
	recording.picks.append({"t": t, "boon": id})
	_refresh_casters()


## Advances the night by dt seconds with the lantern steering toward `target`.
func step(dt: float, target: Vector2) -> void:
	events.clear()
	if is_over():
		return
	prev_player_pos = player_pos
	for s in shadows:
		s.prev_pos = s.pos
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
	_refresh_casters()
	_burn(dt)
	_boons(dt)
	_reap()
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
					var len_sq := d.length_squared()
					if len_sq < min_d * min_d and len_sq > 0.000001:
						var len := sqrt(len_sq)
						var push := d / len * (min_d - len) * 0.5
						a.pos -= push
						b.pos += push


func _refresh_casters() -> void:
	casters.clear()
	casters.append({"pos": player_pos, "boons": boons, "light": -1})
	for i in active_echoes():
		casters.append({"pos": echoes[i].position_at(t), "boons": echoes[i].boons_at(t), "light": i})


func _hurt(s: Shadow, amount: float, light: int) -> void:
	if s.hp <= 0.0:
		return
	s.hp -= amount
	s.burning = 0.0
	if s.hp <= 0.0:
		s.killer = light


func _burn(dt: float) -> void:
	var burn_mult: float = stats["burn_mult"]
	# x, y, radius, dps, light
	var lights: Array[Array] = []
	lights.append([player_pos, light_radius(), Tuning.PLAYER_BURN_DPS * burn_mult, -1])
	for c in casters:
		if c["light"] >= 0:
			lights.append([c["pos"], echo_light_radius(), Tuning.ECHO_BURN_DPS * burn_mult, c["light"]])
	for i in glowing_echoes():
		lights.append([echoes[i].position_at(echoes[i].duration), echo_light_radius() * 0.8, Tuning.ECHO_BURN_DPS * burn_mult, i])
	for s in shadows:
		for L in lights:
			var reach: float = L[1] + s.radius * 0.5
			var d := s.pos.distance_to(L[0])
			if d < reach:
				_hurt(s, L[2] * lerpf(1.0, Tuning.BURN_EDGE_FACTOR, d / reach) * dt, L[3])


func _boons(dt: float) -> void:
	var burn_mult: float = stats["burn_mult"]
	for c in casters:
		var lv: Dictionary = c["boons"]
		if lv.is_empty():
			continue
		var key: int = c["light"]
		if not _timers.has(key):
			_timers[key] = {"flare": t, "candle": t, "spark": t, "last_drop": Vector2.INF}
		var tm: Dictionary = _timers[key]
		var pos: Vector2 = c["pos"]

		var flare: int = lv.get("flare", 0)
		if flare > 0 and t >= tm["flare"]:
			var target := _nearest(pos, Tuning.FLARE_RANGE, [])
			if target != null:
				bolts.append({"pos": pos, "prev_pos": pos, "target": target, "dmg": Tuning.FLARE_DAMAGE * (1.0 + 0.35 * (flare - 1)) * burn_mult, "light": key, "age": 0.0})
				events.append({"type": "flare", "light": key})
				tm["flare"] = t + Tuning.FLARE_INTERVAL / (1.0 + 0.25 * (flare - 1))

		var moths: int = lv.get("moths", 0)
		if moths > 0:
			for m in moth_positions(c):
				for s in shadows:
					if s.pos.distance_squared_to(m) < pow(Tuning.MOTH_RADIUS + s.radius, 2):
						_hurt(s, Tuning.MOTH_DPS * burn_mult * dt, key)

		var candle: int = lv.get("candle", 0)
		if candle > 0 and t >= tm["candle"]:
			tm["candle"] = t + Tuning.CANDLE_INTERVAL
			var last: Vector2 = tm["last_drop"]
			if last == Vector2.INF or last.distance_to(pos) > Tuning.CANDLE_RADIUS * 0.6:
				tm["last_drop"] = pos
				wax.append({"pos": pos, "age": 0.0, "life": Tuning.CANDLE_LIFE + 0.4 * (candle - 1),
					"dps": (Tuning.CANDLE_DPS + 2.0 * (candle - 1)) * burn_mult, "light": key})

		var spark: int = lv.get("spark", 0)
		if spark > 0 and t >= tm["spark"]:
			var first := _nearest(pos, Tuning.SPARK_RANGE, [])
			if first != null:
				tm["spark"] = t + Tuning.SPARK_INTERVAL
				var hit: Array = [first]
				var points := PackedVector2Array([pos, first.pos])
				var dmg := (Tuning.SPARK_DAMAGE + 3.0 * (spark - 1)) * burn_mult
				_hurt(first, dmg, key)
				for j in Tuning.SPARK_JUMPS + spark - 1:
					var next := _nearest(hit[hit.size() - 1].pos, Tuning.SPARK_JUMP, hit)
					if next == null:
						break
					hit.append(next)
					points.append(next.pos)
					_hurt(next, dmg, key)
				events.append({"type": "spark", "points": points, "light": key})

	# Bolts home in on their target; if it dies first they fly on and fizzle.
	for b in bolts:
		b["age"] += dt
		b["prev_pos"] = b["pos"]
		var tgt: Shadow = b["target"]
		var dir: Vector2
		if tgt != null and tgt.hp > 0.0:
			dir = (tgt.pos - b["pos"]).normalized()
			b["dir"] = dir
		else:
			b["target"] = null
			dir = b.get("dir", Vector2.RIGHT)
		b["pos"] += dir * Tuning.FLARE_SPEED * dt
		if b["target"] != null and b["pos"].distance_to(tgt.pos) < tgt.radius + 4.0:
			_hurt(tgt, b["dmg"], b["light"])
			b["age"] = 99.0
	bolts = bolts.filter(func(b): return b["age"] < 1.2)

	for w in wax:
		w["age"] += dt
		for s in shadows:
			if s.pos.distance_squared_to(w["pos"]) < pow(Tuning.CANDLE_RADIUS + s.radius * 0.5, 2):
				_hurt(s, w["dps"] * dt, w["light"])
	wax = wax.filter(func(w): return w["age"] < w["life"])


## Where a caster's Moths are right now.
func moth_positions(c: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n: int = c["boons"].get("moths", 0)
	if n <= 0:
		return out
	n += Tuning.MOTHS_BASE - 1
	var offset: float = float(c["light"] + 1) * 0.9
	for k in n:
		out.append(c["pos"] + Vector2.from_angle(t * Tuning.MOTH_SPEED + TAU * k / n + offset) * Tuning.MOTH_ORBIT)
	return out


func _nearest(from: Vector2, max_dist: float, exclude: Array) -> Shadow:
	var best: Shadow = null
	var best_d := max_dist * max_dist
	for s in shadows:
		if s.hp <= 0.0 or exclude.has(s):
			continue
		var d := s.pos.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = s
	return best


## Removes burned shadows, splits Bloats, and pays out Embers.
func _reap() -> void:
	var survivors: Array[Shadow] = []
	var spawned: Array[Shadow] = []
	for s in shadows:
		if s.hp > 0.0:
			survivors.append(s)
			continue
		burned += 1
		burned_by_kind[s.kind] = burned_by_kind.get(s.kind, 0) + 1
		if s.killer >= 0:
			burned_by_echoes += 1
		events.append({"type": "burn", "pos": s.pos, "kind": s.kind, "light": s.killer})
		var e: float = Tuning.EMBERS_PER_KIND.get(s.kind, 1) * (Tuning.ECHO_EMBER_SHARE if s.killer >= 0 else 1.0)
		_ember_frac += e
		_gain_embers(int(_ember_frac))
		_ember_frac -= int(_ember_frac)
		if s.kind == "bloat":
			events.append({"type": "split", "pos": s.pos})
			for n in Tuning.BLOAT_SPLIT:
				var off := Vector2.from_angle(TAU * n / Tuning.BLOAT_SPLIT + s.phase) * s.radius
				_spawn_count += 1
				spawned.append(Shadow.new("mite", s.pos + off, fmod(_spawn_count * 0.618034, 1.0) * TAU))
	survivors.append_array(spawned)
	shadows = survivors


func _gain_embers(n: int) -> void:
	embers += n
	while embers >= embers_for_next_level():
		embers -= embers_for_next_level()
		level += 1
		# Once every Boon is maxed a level-up has nothing left to offer.
		if _room_for_picks() > 0:
			pending_level_ups += 1
		events.append({"type": "level_up", "level": level})


## Boon levels still to be had this night, beyond the picks already waiting.
func _room_for_picks() -> int:
	var room := 0
	for b in Upgrades.BOONS:
		room += Upgrades.BOON_MAX_LEVEL - int(boons.get(b["id"], 0))
	return room - pending_level_ups


func _contact(dt: float) -> void:
	for s in shadows:
		if s.pos.distance_to(player_pos) < Tuning.PLAYER_RADIUS + s.radius:
			flame -= s.contact_dps * dt
