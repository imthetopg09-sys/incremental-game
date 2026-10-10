extends Node
## Autoload: procedural sound effects. Every sound is synthesized into a short
## 16-bit mono buffer at startup, so the game ships no audio files.
## Synthesis runs on a worker thread so startup never stalls; a sound asked for
## before it finishes waits for it, so nothing is ever dropped.
## Burns ring as notes on a pentatonic scale, one register per voice, so a growing
## army of Echoes becomes a choir. When burns come too fast for single notes, a soft
## chord pad swells under the night instead and fades when the rush is over.

## One-shot players in the pool. Burn notes may use at most BURN_SLOTS of them,
## so a chime or a strike always finds room.
const POOL_SIZE := 10
const BURN_SLOTS := 8
## Burns per second at which single notes give way to the pad, and back again.
const PAD_ON_RATE := 20.0
const PAD_OFF_RATE := 14.0
## Seconds the burn rate takes to forget a burn.
const RATE_TAU := 0.6
## Seconds the pad takes to swell and to fade (time constants).
const PAD_RISE := 0.35
const PAD_FALL := 1.4
## One voice never starts two notes closer together than this, so a burst of burns
## in one frame does not stack the same note into something harsh.
const VOICE_GAP := 0.07
## Big (bloat) notes still ring over the pad, but no closer together than this.
const BIG_GAP := 0.3
const MIX_RATE := 22050
## C major pentatonic, semitones above C.
const SCALE: Array[int] = [0, 2, 4, 7, 9]
## Burn voices: the living lantern, then the Echo hues in EchoRecording.HUES order.
## home: scale degree above C4 (5 is C5). walk: how far notes wander from home.
## big: the low degree a bloat burn rings on. gain: how loud one note is.
const VOICES: Array[Dictionary] = [
	{"home": 2, "walk": 2, "big": -5, "gain": 0.42},  # lantern: E4, warm pluck
	{"home": 4, "walk": 1, "big": -6, "gain": 0.26},  # rose: A4
	{"home": -2, "walk": 1, "big": -7, "gain": 0.30},  # teal: G3
	{"home": 6, "walk": 1, "big": -4, "gain": 0.24},  # violet: D5
	{"home": 8, "walk": 1, "big": -3, "gain": 0.21},  # lime: G5
	{"home": 10, "walk": 1, "big": -2, "gain": 0.19},  # ice: C6
]
## The big note buffer is synthesized on this degree (C3) and pitched per voice.
const BIG_HOME := -5
const BIG_GAIN := 0.5
const PAD_GAIN := 0.45
## Higher priority sounds may take a player from lower ones when the pool is full.
const PRIO_BURN := 0
const PRIO_UI := 1
const PRIO_BIG := 2
const PRIO_FX := 3

## Master volume for every sound, 0..1.
var volume := 0.8:
	set(value):
		volume = clampf(value, 0.0, 1.0)
		_apply_volume()

## How loud the burn pad is right now, 0..1. Above 0 only after a rush of burns.
var pad_level: float:
	get:
		return _pad_level

## One-shot players sounding right now. Never more than POOL_SIZE.
var active_players: int:
	get:
		return _count_active(-1)

## Recent burns per second.
var burn_rate: float:
	get:
		return _rate_now()

var _players: Array[AudioStreamPlayer] = []
var _ends := PackedFloat64Array()
var _starts := PackedFloat64Array()
var _prios := PackedInt32Array()
var _gains := PackedFloat32Array()
var _pad: AudioStreamPlayer = null
var _pad_playing := false
var _pad_on := false
var _pad_level := 0.0
## Seconds since startup, advanced by _process even while the tree is paused.
var _clock := 0.0
var _rate := 0.0
var _rate_at := 0.0
var _voice_at := PackedFloat64Array()
var _walk := PackedInt32Array()
var _big_at := -INF
var _rng := RandomNumberGenerator.new()
## WorkerThreadPool task building the buffers, or -1 once they are in hand.
var _task := -1

var _voice_notes: Array[AudioStreamWAV] = []
var _big_note: AudioStreamWAV = null
var _level_up: AudioStreamWAV = null
var _strike: AudioStreamWAV = null
var _death: AudioStreamWAV = null
var _dawn: AudioStreamWAV = null
var _click: AudioStreamWAV = null
var _pad_loop: AudioStreamWAV = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_task = WorkerThreadPool.add_task(_build_sounds, true, "Sfx synthesis")
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ends.resize(POOL_SIZE)
	_ends.fill(0.0)
	_starts.resize(POOL_SIZE)
	_starts.fill(0.0)
	_prios.resize(POOL_SIZE)
	_prios.fill(PRIO_BURN)
	_gains.resize(POOL_SIZE)
	_gains.fill(0.0)
	_pad = AudioStreamPlayer.new()
	add_child(_pad)
	_voice_at.resize(VOICES.size())
	_voice_at.fill(-INF)
	_walk.resize(VOICES.size())
	_walk.fill(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _process(delta: float) -> void:
	_clock += delta
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_sounds_ready()
	var rate := _rate_now()
	if _pad_on and rate < PAD_OFF_RATE:
		_pad_on = false
	var target := 0.0
	if _pad_on:
		target = clampf(0.45 + (rate - PAD_ON_RATE) / 40.0, 0.45, 1.0)
	var tau := PAD_RISE if target > _pad_level else PAD_FALL
	_pad_level += (target - _pad_level) * (1.0 - exp(-delta / tau))
	if target == 0.0 and _pad_level < 0.004:
		_pad_level = 0.0
	_update_pad()


# --- Public API -------------------------------------------------------------------

## A shadow burned. voice -1 is the living lantern, 0..4 an Echo's hue index.
## big is a bloat: a lower, fuller note.
func burn(voice: int, big := false) -> void:
	var v := 0 if voice < 0 else 1 + posmod(voice, VOICES.size() - 1)
	_rate = _rate_now() + 1.0 / RATE_TAU
	_rate_at = _clock
	if _rate >= PAD_ON_RATE:
		_pad_on = true
	if not _sounds_ready():
		return
	if big:
		if _clock - _big_at < BIG_GAP:
			return
		_big_at = _clock
		_play(_big_note, BIG_GAIN, _ratio(VOICES[v]["big"], BIG_HOME), PRIO_BIG)
		return
	if _pad_on or _clock - _voice_at[v] < VOICE_GAP:
		return
	var burns := _count_active(PRIO_BURN)
	if burns >= BURN_SLOTS:
		return
	_voice_at[v] = _clock
	var walk: int = VOICES[v]["walk"]
	var step := _rng.randi_range(-1, 1)
	if absi(_walk[v] + step) > walk:
		step = -step
	_walk[v] = clampi(_walk[v] + step, -walk, walk)
	var home: int = VOICES[v]["home"]
	# Thin each note a little as the choir gets crowded, so density never gets loud.
	var gain: float = VOICES[v]["gain"] * _rng.randf_range(0.85, 1.0) / (1.0 + 0.07 * burns)
	_play(_voice_notes[v], gain, _ratio(home + _walk[v], home), PRIO_BURN)


## A short rising arpeggio chime.
func level_up() -> void:
	if _sounds_ready():
		_play(_level_up, 0.42, 1.0, PRIO_FX)


## A match strike: a scratch and a bright flare.
func strike() -> void:
	if _sounds_ready():
		_play(_strike, 0.4, 1.0, PRIO_FX)


## The lantern went out: a soft low falling tone.
func death() -> void:
	if _sounds_ready():
		_play(_death, 0.55, 1.0, PRIO_FX)


## Six o'clock: a warm major swell.
func dawn() -> void:
	if _sounds_ready():
		_play(_dawn, 0.5, 1.0, PRIO_FX)


## A tiny tick for buttons.
func ui_click() -> void:
	if _sounds_ready():
		_play(_click, 0.22, _rng.randf_range(0.96, 1.04), PRIO_UI)


## Silences every sound and the pad at once, and forgets the burn rate.
func stop_all() -> void:
	for i in _players.size():
		_players[i].stop()
		_ends[i] = 0.0
	_rate = 0.0
	_pad_on = false
	_pad_level = 0.0
	_update_pad()


# --- Playback ---------------------------------------------------------------------

## Waits for the synthesis task if it is still running. False if there are no sounds.
func _sounds_ready() -> bool:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _pad != null:
			_pad.stream = _pad_loop
	return not _voice_notes.is_empty()


## Call only after _sounds_ready(): the streams are not safe to read before it.
func _play(stream: AudioStreamWAV, gain: float, pitch: float, prio: int) -> bool:
	if stream == null or _players.is_empty() or gain * volume < 0.001:
		return false
	var slot := _free_slot(prio)
	if slot < 0:
		return false
	var p := _players[slot]
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = _db(gain * volume)
	p.play()
	_starts[slot] = _clock
	_ends[slot] = _clock + stream.get_length() / pitch
	_prios[slot] = prio
	_gains[slot] = gain
	return true


## A free player, or the oldest one of the lowest priority this sound may take.
## Burns never take a player from another sound. Returns -1 when there is none.
func _free_slot(prio: int) -> int:
	for i in _players.size():
		if _clock >= _ends[i]:
			return i
	if prio == PRIO_BURN:
		return -1
	var best := -1
	for i in _players.size():
		if _prios[i] > prio:
			continue
		if best < 0 or _prios[i] < _prios[best] or (_prios[i] == _prios[best] and _starts[i] < _starts[best]):
			best = i
	return best


func _count_active(prio: int) -> int:
	var n := 0
	for i in _players.size():
		if _clock < _ends[i] and (prio < 0 or _prios[i] == prio):
			n += 1
	return n


func _rate_now() -> float:
	return _rate * exp(-(_clock - _rate_at) / RATE_TAU)


func _update_pad() -> void:
	if _pad == null:
		return
	if _pad_level <= 0.0 or volume <= 0.0:
		if _pad_playing:
			_pad.stop()
			_pad_playing = false
		return
	_pad.volume_db = _db(_pad_level * PAD_GAIN * volume)
	if not _pad_playing:
		_pad.play()
		_pad_playing = true


func _apply_volume() -> void:
	for i in _players.size():
		if _clock < _ends[i]:
			_players[i].volume_db = _db(_gains[i] * volume)
	_update_pad()


func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.00001))


## MIDI note of a scale degree above C4.
static func _midi(degree: int) -> int:
	return 60 + 12 * floori(degree / 5.0) + SCALE[posmod(degree, 5)]


static func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Pitch scale that turns a buffer made on degree `from` into degree `to`.
static func _ratio(to: int, from: int) -> float:
	return pow(2.0, (_midi(to) - _midi(from)) / 12.0)


# --- Synthesis --------------------------------------------------------------------

func _build_sounds() -> void:
	_voice_notes.clear()
	for v in VOICES.size():
		_voice_notes.append(_make_voice(v))
	_big_note = _make_big()
	_level_up = _make_level_up()
	_strike = _make_strike()
	_death = _make_death()
	_dawn = _make_dawn()
	_click = _make_click()
	_pad_loop = _make_pad()


## The lantern is a warm pluck; Echoes are softer, shimmering glass bells.
func _make_voice(v: int) -> AudioStreamWAV:
	var f := _freq(_midi(VOICES[v]["home"]))
	var b: PackedFloat32Array
	if v == 0:
		b = _buffer(0.9)
		_partial(b, 0.0, f, 1.0, 0.004, 0.3)
		_partial(b, 0.0, f * 1.003, 0.3, 0.008, 0.36)
		_partial(b, 0.0, f * 2.0, 0.32, 0.004, 0.15)
		_partial(b, 0.0, f * 3.0, 0.1, 0.003, 0.08)
		_fade_out(b, 0.2)
	else:
		var tau := clampf(0.45 * sqrt(330.0 / f), 0.26, 0.5)
		b = _buffer(clampf(tau * 3.2, 0.8, 1.5))
		_partial(b, 0.0, f, 1.0, 0.012, tau)
		_partial(b, 0.0, f + 1.3, 0.55, 0.02, tau * 1.15)
		_partial(b, 0.0, f * 2.0, 0.16, 0.008, tau * 0.45)
		_partial(b, 0.0, f * 2.76, 0.06, 0.005, tau * 0.25)
		_fade_out(b, 0.25)
	return _to_wav(b, 0.5)


## A low, round note with a soft thump under it.
func _make_big() -> AudioStreamWAV:
	var f := _freq(_midi(BIG_HOME))
	var b := _buffer(1.5)
	_partial(b, 0.0, f, 1.0, 0.006, 0.5)
	_partial(b, 0.0, f * 1.004, 0.4, 0.012, 0.55)
	_partial(b, 0.0, f * 0.5, 0.35, 0.02, 0.4)
	_partial(b, 0.0, f * 2.0, 0.45, 0.006, 0.3)
	_partial(b, 0.0, f * 3.0, 0.2, 0.005, 0.18)
	_partial(b, 0.0, f * 4.0, 0.08, 0.004, 0.1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	var lp2 := 0.0
	var a := _lowpass(350.0)
	var thump := int(0.07 * MIX_RATE)
	var att := 0.004 * MIX_RATE
	for i in thump:
		lp += a * (rng.randf_range(-1.0, 1.0) - lp)
		lp2 += a * (lp - lp2)
		b[i] += lp2 * 2.5 * minf(i / att, 1.0) * (1.0 - float(i) / thump)
	_fade_out(b, 0.3)
	return _to_wav(b, 0.5)


func _make_level_up() -> AudioStreamWAV:
	var b := _buffer(1.3)
	var notes: Array[int] = [72, 76, 79, 84]
	for i in notes.size():
		var f := _freq(notes[i])
		var t0 := i * 0.075
		var tau := 0.45 if i == notes.size() - 1 else 0.28
		_partial(b, t0, f, 1.0, 0.003, tau)
		_partial(b, t0, f + 1.7, 0.4, 0.006, tau * 1.1)
		_partial(b, t0, f * 2.0, 0.2, 0.003, tau * 0.5)
		_partial(b, t0, f * 3.0, 0.05, 0.002, tau * 0.3)
	_fade_out(b, 0.2)
	return _to_wav(b, 0.5)


## A grainy scratch, then the hiss of the flare catching and a faint glint.
func _make_strike() -> AudioStreamWAV:
	var b := _buffer(0.75)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a1 := _lowpass(4000.0)
	var a2 := _lowpass(900.0)
	var a3 := _lowpass(3000.0)
	var a4 := _lowpass(500.0)
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var lp4 := 0.0
	var grain := 1.0
	for i in b.size():
		var t := float(i) / MIX_RATE
		if i % 60 == 0:
			grain = rng.randf_range(0.15, 1.0)
		var x := rng.randf_range(-1.0, 1.0)
		lp1 += a1 * (x - lp1)
		lp2 += a2 * (x - lp2)
		lp3 += a3 * (x - lp3)
		lp4 += a4 * (x - lp4)
		var scratch := 0.0
		if t < 0.008:
			scratch = t / 0.008
		elif t < 0.09:
			scratch = pow(1.0 - (t - 0.008) / 0.082, 1.5)
		var flare := 0.0
		if t >= 0.05:
			flare = (t - 0.05) / 0.05 if t < 0.1 else exp(-(t - 0.1) / 0.16)
		b[i] += (lp1 - lp2) * scratch * grain + (lp3 - lp4) * flare * 0.5
	_partial(b, 0.06, 2093.0, 0.025, 0.03, 0.18)
	_partial(b, 0.06, 3136.0, 0.012, 0.03, 0.12)
	_fade_out(b, 0.1)
	return _to_wav(b, 0.45)


## A tone that sinks a fifth, from G3 down to C3, and fades.
func _make_death() -> AudioStreamWAV:
	var b := _buffer(2.2)
	var f0 := _freq(55)
	var f1 := _freq(48)
	var ph := 0.0
	var sub := 0.0
	for i in b.size():
		var t := float(i) / MIX_RATE
		var g := minf(t / 1.6, 1.0)
		g = g * g * (3.0 - 2.0 * g)
		var f := f0 * pow(f1 / f0, g) * (1.0 + 0.003 * sin(TAU * 4.5 * t))
		ph += TAU * f / MIX_RATE
		sub += TAU * f * 0.501 / MIX_RATE
		var att := minf(t / 0.12, 1.0)
		var env := att * att * (3.0 - 2.0 * att) * exp(-t / 0.9)
		b[i] = (sin(ph) + 0.2 * sin(2.0 * ph) + 0.3 * sin(sub)) * env
	_fade_out(b, 0.4)
	return _to_wav(b, 0.5)


## A C major chord of slightly detuned pairs that swells in and slowly lets go.
func _make_dawn() -> AudioStreamWAV:
	var b := _buffer(3.4)
	var notes: Array[int] = [48, 55, 64, 67, 72]
	var amps := PackedFloat64Array([1.0, 0.75, 0.55, 0.45, 0.3])
	var w_lo := PackedFloat64Array()
	var w_hi := PackedFloat64Array()
	for m in notes:
		var f := _freq(m)
		w_lo.append(TAU * f * 0.9988 / MIX_RATE)
		w_hi.append(TAU * f * 1.0012 / MIX_RATE)
	var warm := TAU * _freq(48) * 2.0 / MIX_RATE
	for i in b.size():
		var t := float(i) / MIX_RATE
		var env := 1.0
		if t < 1.4:
			env = t / 1.4
			env = env * env * (3.0 - 2.0 * env)
		elif t > 1.9:
			env = 0.5 + 0.5 * cos(PI * minf((t - 1.9) / 1.5, 1.0))
		var s := 0.15 * sin(warm * i)
		for j in notes.size():
			s += amps[j] * (sin(w_lo[j] * i) + sin(w_hi[j] * i))
		b[i] = s * env
	return _to_wav(b, 0.5)


func _make_click() -> AudioStreamWAV:
	var b := _buffer(0.03)
	_partial(b, 0.0, 2400.0, 1.0, 0.0005, 0.004)
	_partial(b, 0.0, 3700.0, 0.4, 0.0003, 0.0025)
	_fade_out(b, 0.005)
	return _to_wav(b, 0.4)


## A two second loop of a soft pentatonic cluster (C3 G3 D4 E4 A4). Every
## frequency is a multiple of 0.5 Hz, so the loop joins without a seam (the buffer
## runs a little past both loop points so the mixer's interpolation reads real
## samples there, not silence), and each
## note beats against a quieter twin so the pad shimmers slowly.
func _make_pad() -> AudioStreamWAV:
	var margin := 64
	var period := 2 * MIX_RATE
	var b := PackedFloat32Array()
	b.resize(period + 2 * margin)
	var notes: Array[int] = [48, 55, 62, 64, 69]
	var amps := PackedFloat64Array([1.0, 0.7, 0.45, 0.4, 0.3])
	var beats := PackedFloat64Array([0.5, 1.0, 0.5, 1.5, 1.0])
	var w := PackedFloat64Array()
	var w2 := PackedFloat64Array()
	var phase := PackedFloat64Array()
	for j in notes.size():
		var f := roundf(_freq(notes[j]) * 2.0) / 2.0
		w.append(TAU * f / MIX_RATE)
		w2.append(TAU * (f + beats[j]) / MIX_RATE)
		phase.append(TAU * j / notes.size())
	for i in b.size():
		var s := 0.0
		for j in notes.size():
			s += amps[j] * (sin(w[j] * i) + 0.7 * sin(w2[j] * i + phase[j]))
		b[i] = s
	return _to_wav(b, 0.5, margin, margin + period)


func _buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * MIX_RATE))
	b.fill(0.0)
	return b


## Adds a sine with a linear attack and an exponential decay, starting at `start` s.
func _partial(b: PackedFloat32Array, start: float, freq: float, amp: float, attack: float, tau: float) -> void:
	var w := TAU * freq / MIX_RATE
	var first := int(start * MIX_RATE)
	var att := maxf(1.0, attack * MIX_RATE)
	var k := exp(-1.0 / (tau * MIX_RATE))
	var env := amp
	var quiet := amp * 0.001
	for n in b.size() - first:
		var a := env if n >= att else env * n / att
		b[first + n] += sin(w * n) * a
		env *= k
		if env < quiet:
			break


func _fade_out(b: PackedFloat32Array, seconds: float) -> void:
	var n := mini(int(seconds * MIX_RATE), b.size())
	for i in n:
		b[b.size() - n + i] *= 0.5 + 0.5 * cos(PI * float(i) / n)


## One-pole low-pass coefficient for a cutoff in Hz.
func _lowpass(cutoff: float) -> float:
	return 1.0 - exp(-TAU * cutoff / MIX_RATE)


## Normalizes to `peak` and packs into a 16-bit mono stream.
## A loop_end above 0 makes it loop forward between the two frames.
func _to_wav(b: PackedFloat32Array, peak: float, loop_begin := 0, loop_end := 0) -> AudioStreamWAV:
	var top := 0.0
	for x in b:
		top = maxf(top, absf(x))
	var scale := peak * 32767.0 / top if top > 0.0 else 0.0
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(b[i] * scale))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = false
	s.data = bytes
	if loop_end > 0:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = loop_begin
		s.loop_end = loop_end
	return s
