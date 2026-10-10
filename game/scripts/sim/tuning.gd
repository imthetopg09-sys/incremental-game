class_name Tuning
extends RefCounted
## Every balance number for the night lives here so it can be tuned in one place.

const ARENA_SIZE := Vector2(1280, 720)
const NIGHT_SEED := 1  # Same seed every night: the shadows come from the same places.

# Night clock: 6 in-game hours, 12:00 AM to 6:00 AM.
const HOUR_LENGTH := 60.0
const NIGHT_HOURS := 6
const NIGHT_LENGTH := HOUR_LENGTH * NIGHT_HOURS

# The living lantern.
const PLAYER_SPEED := 250.0
const PLAYER_RADIUS := 10.0
const PLAYER_MAX_FLAME := 100.0
const PLAYER_LIGHT_RADIUS := 120.0
const PLAYER_BURN_DPS := 7.5
## The light shrinks with the flame: at zero flame it is this fraction of full size.
const LIGHT_AT_EMPTY_FLAME := 0.45
## Burn damage at the edge of a light, relative to its center.
const BURN_EDGE_FACTOR := 0.35

# Echoes: replays of earlier runs.
const ECHO_LIGHT_RADIUS := 85.0
const ECHO_BURN_DPS := 28.0
const START_SCONCES := 3
const FORESIGHT_SECONDS := 1.5

# Shadow kinds. hp, speed, radius, contact damage per second.
const SHADOWS := {
	"wisp": {"hp": 12.0, "speed": 55.0, "radius": 12.0, "contact_dps": 25.0},
	"creeper": {"hp": 7.0, "speed": 125.0, "radius": 9.0, "contact_dps": 14.0},
	"bloat": {"hp": 45.0, "speed": 36.0, "radius": 22.0, "contact_dps": 34.0},
	"mite": {"hp": 4.0, "speed": 85.0, "radius": 7.0, "contact_dps": 9.0},
}
const BLOAT_SPLIT := 4

# Spawning: each kind starts at `start` seconds; its interval shrinks over the night
# as base / (1 + (t - start) / ramp), never below `min`.
const SPAWNS := {
	"wisp": {"start": 0.0, "base": 1.0, "ramp": 40.0, "min": 0.22},
	"creeper": {"start": 60.0, "base": 3.0, "ramp": 60.0, "min": 0.55},
	"bloat": {"start": 120.0, "base": 7.0, "ramp": 80.0, "min": 1.6},
}
const SPAWN_MARGIN := 30.0
