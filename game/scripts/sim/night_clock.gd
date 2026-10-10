class_name NightClock
extends RefCounted
## Converts seconds into the night into the in-game clock (12:00 AM to 6:00 AM).


static func hour_index(t: float) -> int:
	return clampi(int(t / Tuning.HOUR_LENGTH), 0, Tuning.NIGHT_HOURS)


static func label(t: float) -> String:
	var total_minutes := int(clampf(t, 0.0, Tuning.NIGHT_LENGTH) / Tuning.HOUR_LENGTH * 60.0)
	var hour := total_minutes / 60
	var minute := total_minutes % 60
	return "%d:%02d AM" % [12 if hour == 0 else hour, minute]


static func duration_label(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
