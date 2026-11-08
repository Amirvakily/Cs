extends Node
## Procedural sound effects: every sound is synthesised at startup (no audio files),
## then played through pooled 2D / 3D players.

const SR := 22050
var streams := {}
var ready_flag := false
var _p2d: Array[AudioStreamPlayer] = []
var _p3d: Array[AudioStreamPlayer3D] = []
var _i2d := 0
var _i3d := 0
var _thread: Thread
var _rng := RandomNumberGenerator.new()
var _ambient: AudioStreamPlayer


func _ready() -> void:
	for i in 28:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_p2d.append(p)
	for i in 56:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 110.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.attenuation_filter_cutoff_hz = 6000.0
		p3.attenuation_filter_db = -18.0
		p3.panning_strength = 1.0
		add_child(p3)
		_p3d.append(p3)
	_ambient = AudioStreamPlayer.new()
	_ambient.volume_db = -14.0
	add_child(_ambient)
	_thread = Thread.new()
	_thread.start(_generate_all)


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


func wait_ready() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# --- Playback ----------------------------------------------------------------
func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not ready_flag or not streams.has(name):
		return
	var p := _p2d[_i2d]
	_i2d = (_i2d + 1) % _p2d.size()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func has(name: String) -> bool:
	return streams.has(name)


func play3d(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_dist := 110.0) -> void:
	if not ready_flag or not streams.has(name):
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > max_dist:
		return
	var p := _p3d[_i3d]
	_i3d = (_i3d + 1) % _p3d.size()
	p.stream = streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * _rng.randf_range(0.95, 1.05)
	p.max_distance = max_dist
	p.global_position = pos
	p.play()


func play_ambient(name: String) -> void:
	if not ready_flag or not streams.has(name):
		_ambient.stop()
		return
	_ambient.stream = streams[name]
	_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


# --- Synthesis helpers -------------------------------------------------------
func _buf(sec: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(sec * SR))
	return b


func _noise_layer(b: PackedFloat32Array, amp: float, tau: float, lp: float, hp := 0.0, start := 0.0, attack := 0.0005) -> void:
	var a_lp := 1.0 - exp(-TAU * lp / SR)
	var a_hp := 1.0 - exp(-TAU * maxf(hp, 1.0) / SR)
	var y := 0.0
	var yl := 0.0
	var s0 := int(start * SR)
	for i in range(s0, b.size()):
		var t := float(i - s0) / SR
		var env := exp(-t / tau)
		if t < attack:
			env *= t / attack
		var x := _rng.randf_range(-1.0, 1.0)
		y += a_lp * (x - y)
		var o := y
		if hp > 0.0:
			yl += a_hp * (y - yl)
			o = y - yl
		b[i] += o * amp * env
		if env < 0.0005 and t > attack:
			break


func _tone(b: PackedFloat32Array, amp: float, f0: float, f1: float, tau: float, start := 0.0, dur := -1.0, wave := 0) -> void:
	var s0 := int(start * SR)
	var n := b.size() - s0
	if dur > 0.0:
		n = mini(n, int(dur * SR))
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var k := float(i) / maxf(1.0, float(n))
		var f := lerpf(f0, f1, k)
		ph += TAU * f / SR
		var v := sin(ph)
		if wave == 1:
			v = signf(v) * 0.7
		elif wave == 2:
			v = (fmod(ph / TAU, 1.0) * 2.0 - 1.0) * 0.7
		var env := exp(-t / tau) * minf(1.0, t / 0.002)
		b[s0 + i] += v * amp * env


func _reverb(b: PackedFloat32Array, delay: float, fb: float, mix: float) -> void:
	var d := int(delay * SR)
	if d <= 0:
		return
	var out := b.duplicate()
	for i in range(d, b.size()):
		out[i] += out[i - d] * fb
	for i in b.size():
		b[i] = lerpf(b[i], out[i], mix)


func _finish(b: PackedFloat32Array, gain := 1.0, loop := false) -> AudioStreamWAV:
	var peak := 0.0001
	for v in b:
		peak = maxf(peak, absf(v))
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	var norm := gain / peak
	for i in b.size():
		var v := tanh(b[i] * norm * 1.2) / tanh(1.2)
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = SR
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = b.size()
	return s


func _gunshot(len_s: float, crack: float, body_lp: float, body_tau: float, thump_f: float, thump_tau: float, tail_tau: float, gain := 0.95) -> AudioStreamWAV:
	var b := _buf(len_s)
	_noise_layer(b, crack, 0.004, 9000.0, 800.0)
	_noise_layer(b, 0.9, body_tau, body_lp, 120.0)
	_tone(b, 1.0, thump_f * 1.6, thump_f * 0.6, thump_tau)
	_noise_layer(b, 0.35, tail_tau, 900.0, 60.0, 0.01, 0.01)
	_reverb(b, 0.047, 0.35, 0.35)
	return _finish(b, gain)


func _click(freq: float, len_s := 0.06, amp := 1.0) -> PackedFloat32Array:
	var b := _buf(len_s)
	_noise_layer(b, amp, 0.004, 7000.0, 1500.0)
	_tone(b, amp * 0.6, freq, freq * 0.9, 0.012)
	return b


func _generate_all() -> void:
	_rng.seed = 1337
	var s := {}
	# Weapons
	s["pistol"] = _gunshot(0.45, 1.0, 3200.0, 0.035, 140.0, 0.05, 0.12)
	s["magnum"] = _gunshot(0.8, 1.2, 2400.0, 0.06, 90.0, 0.09, 0.25)
	s["smg"] = _gunshot(0.35, 0.9, 3800.0, 0.028, 160.0, 0.04, 0.09)
	s["rifle"] = _gunshot(0.6, 1.1, 2800.0, 0.045, 110.0, 0.07, 0.18)
	s["rifle_heavy"] = _gunshot(0.7, 1.2, 2200.0, 0.055, 85.0, 0.09, 0.22)
	s["shotgun"] = _gunshot(0.9, 1.0, 1600.0, 0.09, 70.0, 0.12, 0.3)
	s["sniper"] = _gunshot(1.3, 1.4, 2000.0, 0.08, 65.0, 0.14, 0.45, 1.0)
	s["sniper_light"] = _gunshot(0.9, 1.2, 2600.0, 0.06, 95.0, 0.1, 0.3)
	var b := _buf(0.3)
	_noise_layer(b, 0.8, 0.08, 2500.0, 600.0, 0.0, 0.05)
	s["knife"] = _finish(b, 0.5)
	b = _buf(0.25)
	_noise_layer(b, 1.0, 0.03, 1200.0, 80.0)
	_tone(b, 0.8, 180.0, 90.0, 0.04)
	s["knife_hit"] = _finish(b, 0.8)
	s["dry"] = _finish(_click(2400.0, 0.05, 0.6), 0.4)
	s["mag_out"] = _finish(_click(1400.0, 0.12, 1.0), 0.55)
	b = _click(1800.0, 0.14, 1.0)
	_tone(b, 0.4, 3200.0, 3000.0, 0.02, 0.03)
	s["mag_in"] = _finish(b, 0.65)
	b = _click(2100.0, 0.25, 1.0)
	var b2 := _click(1600.0, 0.12, 1.0)
	for i in b2.size():
		if i + int(0.11 * SR) < b.size():
			b[i + int(0.11 * SR)] += b2[i]
	s["bolt"] = _finish(b, 0.6)
	s["pump"] = s["bolt"]
	b = _buf(0.12)
	_noise_layer(b, 1.0, 0.02, 900.0, 200.0)
	_tone(b, 0.5, 2600.0, 2400.0, 0.02)
	s["shell"] = _finish(b, 0.4)
	# Movement
	for i in 4:
		b = _buf(0.14)
		_noise_layer(b, 1.0, 0.025 + i * 0.004, 700.0 + i * 160.0, 90.0)
		_noise_layer(b, 0.35, 0.012, 4000.0, 1500.0, 0.004)
		s["step%d" % i] = _finish(b, 0.5)
	b = _buf(0.25)
	_noise_layer(b, 1.0, 0.05, 500.0, 50.0)
	_tone(b, 0.6, 90.0, 50.0, 0.05)
	s["land"] = _finish(b, 0.6)
	# Impacts
	b = _buf(0.18)
	_noise_layer(b, 1.0, 0.015, 6000.0, 1200.0)
	_noise_layer(b, 0.4, 0.04, 1500.0, 200.0, 0.005)
	s["imp_concrete"] = _finish(b, 0.5)
	b = _buf(0.4)
	_noise_layer(b, 0.6, 0.006, 8000.0, 2000.0)
	_tone(b, 0.7, 2900.0, 2700.0, 0.09)
	_tone(b, 0.4, 4300.0, 4100.0, 0.06)
	s["imp_metal"] = _finish(b, 0.5)
	b = _buf(0.22)
	_noise_layer(b, 1.0, 0.025, 1800.0, 150.0)
	_tone(b, 0.5, 320.0, 240.0, 0.03)
	s["imp_wood"] = _finish(b, 0.5)
	b = _buf(0.2)
	_noise_layer(b, 1.0, 0.03, 900.0, 80.0)
	_tone(b, 0.6, 120.0, 70.0, 0.04)
	s["imp_flesh"] = _finish(b, 0.6)
	b = _buf(0.5)
	_tone(b, 0.9, 3600.0, 3500.0, 0.12)
	_tone(b, 0.5, 5200.0, 5100.0, 0.08)
	_noise_layer(b, 0.4, 0.005, 9000.0, 3000.0)
	s["headshot"] = _finish(b, 0.55)
	b = _buf(0.06)
	_tone(b, 1.0, 1900.0, 1800.0, 0.02)
	s["hitmark"] = _finish(b, 0.35)
	# Bullet passing close by: a sharp supersonic crack followed by a falling whizz.
	for k in 3:
		b = _buf(0.32)
		_noise_layer(b, 1.0, 0.004, 9000.0, 2500.0)
		var ph2 := 0.0
		for i in b.size():
			var t := float(i) / SR
			var f := lerpf(2600.0 + k * 300.0, 700.0, minf(t / 0.22, 1.0))
			ph2 += TAU * f / SR
			b[i] += (_rng.randf_range(-1.0, 1.0) * 0.5 + sin(ph2) * 0.25) * exp(-t / 0.07) * minf(1.0, t / 0.01) * 0.6
		s["whizz%d" % k] = _finish(b, 0.55)
	b = _buf(0.25)
	_noise_layer(b, 0.5, 0.01, 7000.0, 2000.0)
	_tone(b, 0.6, 1100.0, 900.0, 0.03)
	s["bounce"] = _finish(b, 0.35)
	s["pin"] = _finish(_click(3000.0, 0.1, 1.0), 0.45)
	# Explosions
	b = _buf(2.2)
	_noise_layer(b, 1.0, 0.012, 9000.0, 300.0)
	_noise_layer(b, 1.0, 0.35, 700.0, 25.0, 0.0, 0.004)
	_tone(b, 1.0, 90.0, 28.0, 0.35)
	_noise_layer(b, 0.4, 0.9, 300.0, 20.0, 0.05, 0.05)
	_reverb(b, 0.09, 0.4, 0.4)
	s["explode"] = _finish(b, 1.0)
	b = _buf(1.0)
	_noise_layer(b, 1.0, 0.02, 9000.0, 600.0)
	_noise_layer(b, 0.7, 0.15, 3000.0, 100.0)
	_tone(b, 0.6, 140.0, 60.0, 0.12)
	_reverb(b, 0.06, 0.3, 0.3)
	s["flashbang"] = _finish(b, 1.0)
	b = _buf(3.0)
	_tone(b, 0.5, 3500.0, 3400.0, 1.4)
	s["ring"] = _finish(b, 0.25)
	b = _buf(2.5)
	_noise_layer(b, 1.0, 0.9, 7000.0, 2500.0, 0.0, 0.1)
	s["smoke"] = _finish(b, 0.35)
	# Objective
	b = _buf(0.1)
	_tone(b, 1.0, 2000.0, 2000.0, 0.05, 0.0, -1.0, 1)
	s["beep"] = _finish(b, 0.35)
	b = _buf(0.9)
	for k in 5:
		_tone(b, 0.8, 1400.0 + k * 180.0, 1400.0 + k * 180.0, 0.04, k * 0.14, 0.07, 1)
	s["plant"] = _finish(b, 0.4)
	b = _buf(0.3)
	_noise_layer(b, 0.5, 0.01, 6000.0, 1500.0)
	_tone(b, 0.5, 900.0, 700.0, 0.03)
	_tone(b, 0.5, 1300.0, 1100.0, 0.03, 0.12)
	s["defuse"] = _finish(b, 0.4)
	b = _buf(0.8)
	_tone(b, 0.7, 880.0, 880.0, 0.2, 0.0, 0.25)
	_tone(b, 0.7, 1320.0, 1320.0, 0.25, 0.22, 0.4)
	s["defused"] = _finish(b, 0.45)
	# Doors & breach
	b = _buf(0.7)
	var ph := 0.0
	for i in b.size():
		var t := float(i) / SR
		ph += TAU * (210.0 + 60.0 * sin(t * 23.0) + 120.0 * t) / SR
		b[i] += sin(ph) * 0.25 * exp(-t / 0.4) * minf(1.0, t / 0.05)
	_noise_layer(b, 0.5, 0.25, 1200.0, 200.0, 0.0, 0.05)
	s["door_open"] = _finish(b, 0.4)
	b = _buf(0.35)
	_noise_layer(b, 1.0, 0.05, 700.0, 60.0)
	_tone(b, 0.7, 110.0, 70.0, 0.06)
	s["door_close"] = _finish(b, 0.6)
	b = _buf(0.7)
	for k in 9:
		_noise_layer(b, 0.7, 0.02, 2500.0, 300.0, _rng.randf() * 0.4, 0.001)
	_tone(b, 0.5, 200.0, 120.0, 0.06)
	s["wood_break"] = _finish(b, 0.65)
	# UI / radio
	b = _buf(0.18)
	_tone(b, 0.8, 1200.0, 1200.0, 0.04, 0.0, 0.06)
	_tone(b, 0.8, 1800.0, 1800.0, 0.04, 0.07, 0.08)
	s["buy"] = _finish(b, 0.35)
	b = _buf(0.05)
	_tone(b, 1.0, 900.0, 900.0, 0.015)
	s["click"] = _finish(b, 0.3)
	b = _buf(0.3)
	_noise_layer(b, 0.6, 0.08, 4000.0, 1200.0)
	_tone(b, 0.5, 1000.0, 1000.0, 0.03, 0.0, 0.05, 1)
	s["radio"] = _finish(b, 0.3)
	b = _buf(1.4)
	var notes := [523.0, 659.0, 784.0, 1047.0]
	for k in notes.size():
		_tone(b, 0.6, notes[k], notes[k], 0.25, k * 0.13, 0.5, 2)
	s["win"] = _finish(b, 0.4)
	b = _buf(1.4)
	notes = [392.0, 349.0, 311.0, 262.0]
	for k in notes.size():
		_tone(b, 0.6, notes[k], notes[k], 0.3, k * 0.16, 0.5, 2)
	s["lose"] = _finish(b, 0.4)
	b = _buf(0.5)
	_tone(b, 0.6, 600.0, 600.0, 0.05, 0.0, 0.1, 1)
	_tone(b, 0.6, 900.0, 900.0, 0.05, 0.15, 0.15, 1)
	s["round_start"] = _finish(b, 0.35)
	# Ambience loops
	b = _buf(8.0)
	var y := 0.0
	for i in b.size():
		var t := float(i) / SR
		y += 0.02 * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * (0.6 + 0.4 * sin(TAU * t / 8.0 * 2.0) * sin(TAU * t / 8.0 * 3.0))
	s["amb_wind"] = _finish(b, 0.5, true)
	b = _buf(8.0)
	y = 0.0
	for i in b.size():
		var t := float(i) / SR
		y += 0.05 * (_rng.randf_range(-1.0, 1.0) - y)
		b[i] = y * 0.8 + sin(TAU * 60.0 * t) * 0.05 + sin(TAU * 120.0 * t) * 0.03
	s["amb_city"] = _finish(b, 0.5, true)
	call_deferred("_on_generated", s)


## Recorded CC0 sounds (assets/sounds, built by tools/build_sounds.py) override synthesized ones.
const RECORDED := ["shot_m9", "shot_raptor", "shot_hawk", "shot_vespa", "shot_mako", "shot_breacher", "shot_kv74",
	"shot_ar7", "shot_hornet", "shot_sentry", "shot_longbow", "shot_thresher", "reload_pistol", "reload_rifle",
	"reload_smg", "reload_alt", "bolt", "pump", "shell_insert"]


func _on_generated(s: Dictionary) -> void:
	for key in RECORDED:
		for suffix in ["", "_far"]:
			var path := "res://assets/sounds/%s%s.ogg" % [key, suffix]
			if ResourceLoader.exists(path):
				s[key + suffix] = load(path)
	streams = s
	ready_flag = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
