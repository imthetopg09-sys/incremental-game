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


static func hue_for_run(run: int) -> Color:
	return HUES[posmod(run - 1, HUES.size())]


func hue() -> Color:
	return hue_for_run(run_number)


## Records the position for every sample time up to `time`.
func record_until(time: float, pos: Vector2) -> void:
	while points.size() <= int(time * RATE):
		points.append(pos)


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
	if from_time > 0.0 and from_time <= duration:
		out.append(position_at(from_time))
	for i in range(a, b + 1):
		out.append(points[i])
	if to_time < duration and to_time > 0.0:
		out.append(position_at(to_time))
	return out


func to_dict() -> Dictionary:
	var flat := PackedFloat32Array()
	for p in points:
		flat.append(p.x)
		flat.append(p.y)
	return {"points": flat, "duration": duration, "died": died, "run": run_number, "burned": burned}


static func from_dict(d: Dictionary) -> EchoRecording:
	var r := EchoRecording.new()
	var flat: PackedFloat32Array = d.get("points", PackedFloat32Array())
	for i in range(0, flat.size() - 1, 2):
		r.points.append(Vector2(flat[i], flat[i + 1]))
	r.duration = d.get("duration", 0.0)
	r.died = d.get("died", true)
	r.run_number = d.get("run", 0)
	r.burned = d.get("burned", 0)
	return r
