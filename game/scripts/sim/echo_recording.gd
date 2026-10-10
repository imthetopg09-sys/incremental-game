class_name EchoRecording
extends RefCounted
## One run's path, sampled at a fixed rate, replayed later as an Echo.

const RATE := 30.0
## Echo colors, picked by run number.
const HUES: Array[Color] = [
	Color(1.0, 0.45, 0.62),  # rose
	Color(0.30, 0.90, 0.85),  # teal
	Color(0.70, 0.52, 1.0),  # violet
	Color(0.66, 0.95, 0.35),  # lime
	Color(0.62, 0.86, 1.0),  # ice
]

var points := PackedVector2Array()
var duration := 0.0
var died := true
var run_number := 0
var burned := 0
## Index into HUES, chosen when the Echo is kept so kept Echoes never share a color.
var hue_index := -1
## Boons drafted during the run, replayed by the Echo at the same moments:
## [{"t": seconds, "boon": id}], in time order.
var picks: Array[Dictionary] = []
## Other runs braided into this one (a Chorus): they share its Sconce and color.
var chorus: Array[EchoRecording] = []


## Boon levels this run had reached by `time`.
func boons_at(time: float) -> Dictionary:
	var out := {}
	for p in picks:
		if p["t"] > time:
			break
		out[p["boon"]] = out.get(p["boon"], 0) + 1
	return out


## This Echo and every run braided into it.
func members() -> Array[EchoRecording]:
	var out: Array[EchoRecording] = [self]
	out.append_array(chorus)
	return out


func hue() -> Color:
	return HUES[posmod(hue_index if hue_index >= 0 else run_number - 1, HUES.size())]


## Records the position for every sample time up to `time`.
func record_until(time: float, pos: Vector2) -> void:
	# The epsilon absorbs float drift from accumulating dt, so sample i lands on
	# the step at time i / RATE instead of one step late.
	# Stored at the quarter-pixel precision the save keeps, so an Echo loaded from
	# disk walks exactly the path it walked in memory.
	var stored := (pos * 4.0).round() / 4.0
	while points.size() <= int(time * RATE + 1e-6):
		points.append(stored)
	duration = maxf(duration, time)


func finish(time: float, pos: Vector2, did_die: bool) -> void:
	record_until(time, pos)
	duration = time
	died = did_die


func is_active(time: float) -> bool:
	return time <= duration and not points.is_empty()


func position_at(time: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var f := clampf(time, 0.0, duration) * RATE
	var i := int(f)
	if i >= points.size() - 1:
		return points[points.size() - 1]
	return points[i].lerp(points[i + 1], f - i)


## Positions from `from_time` to `to_time` (clamped to the recording), one per sample.
func path_between(from_time: float, to_time: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.is_empty():
		return out
	var a := clampi(int(ceil(maxf(from_time, 0.0) * RATE)), 0, points.size() - 1)
	var b := clampi(int(floor(minf(to_time, duration) * RATE)), 0, points.size() - 1)
	if b < a:
		return out
	out = points.slice(a, b + 1)
	if from_time > 0.0 and from_time <= duration:
		out.insert(0, position_at(from_time))
	if to_time < duration and to_time > 0.0:
		out.append(position_at(to_time))
	return out


## JSON-safe form. Points are stored as quarter-pixel int16 pairs in base64, so a
## full-night run is about 57 KB of text instead of a few hundred KB of numbers.
func to_dict() -> Dictionary:
	var bytes := PackedByteArray()
	bytes.resize(points.size() * 4)
	for i in points.size():
		bytes.encode_s16(i * 4, clampi(roundi(points[i].x * 4.0), -32768, 32767))
		bytes.encode_s16(i * 4 + 2, clampi(roundi(points[i].y * 4.0), -32768, 32767))
	return {
		"points": Marshalls.raw_to_base64(bytes),
		"duration": duration,
		"died": died,
		"run": run_number,
		"burned": burned,
		"hue": hue_index,
		"picks": picks.duplicate(true),
		"chorus": chorus.map(func(c): return c.to_dict()),
	}


static func from_dict(d: Dictionary) -> EchoRecording:
	var r := EchoRecording.new()
	var bytes := Marshalls.base64_to_raw(str(d.get("points", "")))
	for i in range(0, bytes.size() - 3, 4):
		r.points.append(Vector2(bytes.decode_s16(i), bytes.decode_s16(i + 2)) / 4.0)
	r.duration = float(d.get("duration", 0.0))
	r.died = bool(d.get("died", true))
	r.run_number = int(d.get("run", 0))
	r.burned = int(d.get("burned", 0))
	r.hue_index = int(d.get("hue", -1))
	for p in d.get("picks", []):
		r.picks.append({"t": float(p.get("t", 0.0)), "boon": str(p.get("boon", ""))})
	for c in d.get("chorus", []):
		r.chorus.append(EchoRecording.from_dict(c))
	return r
