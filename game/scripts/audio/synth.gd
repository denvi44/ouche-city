class_name Synth
extends RefCounted
## Synthèse sonore d'Ouche City (agent 08) : tous les sons sont générés par le code.
## Pourquoi : aucun fichier binaire à versionner (LFS), aucune question de licence, et chaque
## son est reproductible à partir de ses paramètres, écrits ici. Remplaçable plus tard par des
## enregistrements (`Sfx` cherche d'abord `res://assets/audio/<nom>.ogg|wav`).
##
## Toutes les fonctions `static` renvoient des échantillons flottants mono dans [-1, 1] à `RATE` Hz
## (pures, donc testables). `to_stream` les convertit en AudioStreamWAV 16 bits.

const RATE := 22050
const TABLE_SIZE := 1024

static var _tables := {}
static var _rng := RandomNumberGenerator.new()


# --- Outils ---------------------------------------------------------------------------------------

static func _buf(seconds: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(maxi(int(seconds * RATE), 1))
	return a


## Table d'onde d'un cycle : somme d'harmoniques (amplitudes données), normalisée.
static func table(name: String, harmonics: Array) -> PackedFloat32Array:
	if _tables.has(name):
		return _tables[name]
	var t := PackedFloat32Array()
	t.resize(TABLE_SIZE)
	var peak := 0.0001
	for i in TABLE_SIZE:
		var ph := TAU * float(i) / TABLE_SIZE
		var v := 0.0
		for k in harmonics.size():
			v += float(harmonics[k]) * sin(ph * (k + 1))
		t[i] = v
		peak = maxf(peak, absf(v))
	for i in TABLE_SIZE:
		t[i] /= peak
	_tables[name] = t
	return t


static func _sine() -> PackedFloat32Array:
	return table("sine", [1.0])


## Anche d'accordéon : riche en harmoniques impaires et paires, timbre nasillard.
static func _reed() -> PackedFloat32Array:
	return table("reed", [1.0, 0.55, 0.7, 0.3, 0.45, 0.2, 0.25, 0.12, 0.1])


static func _square() -> PackedFloat32Array:
	return table("square", [1.0, 0.0, 0.33, 0.0, 0.2, 0.0, 0.14])


static func _saw() -> PackedFloat32Array:
	return table("saw", [1.0, 0.5, 0.33, 0.25, 0.2, 0.166, 0.14, 0.125])


static func _lookup(t: PackedFloat32Array, phase: float) -> float:
	var x: float = (phase - floorf(phase)) * float(TABLE_SIZE)
	var i: int = int(x)
	var f: float = x - float(i)
	return lerpf(t[i], t[(i + 1) % TABLE_SIZE], f)


## Enveloppe attaque / maintien / relâchement (en secondes) évaluée au temps `t` d'une durée `dur`.
static func _env(t: float, dur: float, attack := 0.01, release := 0.05) -> float:
	var a := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var r := clampf((dur - t) / maxf(release, 0.0001), 0.0, 1.0)
	return a * r


static func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


## Normalise au pic donné (pour que tous les sons aient des niveaux comparables).
static func normalized(a: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	var g := peak / m
	var out := a.duplicate()
	for i in out.size():
		out[i] = a[i] * g
	return out


static func to_stream(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# --- Effets sonores ---------------------------------------------------------------------------------

## Klaxon : deux notes en tierce (sol4 + si4), deux coups brefs « pouet-pouet ».
static func klaxon() -> PackedFloat32Array:
	var out := _buf(0.62)
	var t := _square()
	for i in out.size():
		var s := float(i) / RATE
		var gate := 1.0 if (s < 0.22 or (s > 0.3 and s < 0.58)) else 0.0
		var local := s if s < 0.3 else s - 0.3
		var v := _lookup(t, 392.0 * s) * 0.5 + _lookup(t, 494.0 * s) * 0.5
		out[i] = v * gate * _env(local, 0.28, 0.008, 0.04)
	return normalized(out, 0.8)


## Moteur de camionnette : boucle de 0,5 s à 50 Hz (cycles entiers : raccord sans clic),
## modulée par les « cylindres » à 20 Hz. La hauteur se règle avec `pitch_scale`.
static func engine_loop() -> PackedFloat32Array:
	var out := _buf(0.5)
	var t := _saw()
	for i in out.size():
		var s := float(i) / RATE
		var base := _lookup(t, 50.0 * s) * 0.6 + _lookup(_sine(), 100.0 * s) * 0.4
		var am := 0.65 + 0.35 * sin(TAU * 20.0 * s)
		out[i] = base * am
	return normalized(out, 0.7)


## Tracteur : « teuf-teuf » grave et lent, 1 s en boucle (6 coups).
static func tractor_loop() -> PackedFloat32Array:
	var out := _buf(1.0)
	for i in out.size():
		var s := float(i) / RATE
		var beat := fmod(s * 6.0, 1.0)
		var decay := exp(-beat * 7.0)
		var v := _lookup(_sine(), 62.0 * s) * 0.7 + _lookup(_saw(), 124.0 * s) * 0.3
		out[i] = v * decay
	return normalized(out, 0.75)


## Choc dans un nid-de-poule : coup sourd qui retombe de 90 à 45 Hz + un peu de gravier.
static func thud() -> PackedFloat32Array:
	var out := _buf(0.35)
	var ph := 0.0
	for i in out.size():
		var s := float(i) / RATE
		var f := lerpf(90.0, 45.0, clampf(s / 0.25, 0.0, 1.0))
		ph += f / RATE
		out[i] = (sin(TAU * ph) * exp(-s * 9.0) + _noise() * 0.25 * exp(-s * 40.0))
	return normalized(out, 0.9)


## Bouteille qui casse : claquement de bruit, puis des éclats cristallins aigus qui s'éteignent.
static func glass() -> PackedFloat32Array:
	_rng.seed = 7
	var out := _buf(0.7)
	var freqs := [2300.0, 3100.0, 3900.0, 4700.0, 5600.0]
	var starts := [0.0, 0.04, 0.09, 0.15, 0.22]
	for i in out.size():
		var s := float(i) / RATE
		var v := _noise() * 0.5 * exp(-s * 55.0)
		for k in freqs.size():
			var ls: float = s - float(starts[k])
			if ls > 0.0:
				v += sin(TAU * float(freqs[k]) * ls) * 0.3 * exp(-ls * 14.0)
		out[i] = v
	return normalized(out, 0.85)


## Caisse de bois : deux coups secs, résonance de planche vers 190 Hz.
static func crate() -> PackedFloat32Array:
	_rng.seed = 11
	var out := _buf(0.3)
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for hit in [0.0, 0.11]:
			var ls: float = s - float(hit)
			if ls > 0.0:
				v += (sin(TAU * 190.0 * ls) * 0.8 + sin(TAU * 410.0 * ls) * 0.3) * exp(-ls * 28.0)
				v += _noise() * 0.2 * exp(-ls * 90.0)
		out[i] = v
	return normalized(out, 0.85)


## Meuglement : voix grave qui monte puis retombe, vibrato lent, timbre d'anche filtré.
static func moo() -> PackedFloat32Array:
	var out := _buf(1.3)
	var ph := 0.0
	var ph2 := 0.0
	for i in out.size():
		var s := float(i) / RATE
		var shape := sin(PI * clampf(s / 1.3, 0.0, 1.0))
		var f := 96.0 + 26.0 * sin(PI * clampf(s / 0.7, 0.0, 1.0)) - 14.0 * clampf((s - 0.7) / 0.6, 0.0, 1.0)
		f *= 1.0 + 0.015 * sin(TAU * 5.5 * s)
		ph += f / RATE
		ph2 += f * 2.01 / RATE
		var v := _lookup(_reed(), ph) * 0.8 + _lookup(_sine(), ph2) * 0.3
		out[i] = v * pow(shape, 0.7) * _env(s, 1.3, 0.05, 0.25)
	return normalized(out, 0.85)


## Petit carillon d'arpège (ramasser, charger, valider).
static func chime() -> PackedFloat32Array:
	var out := _buf(0.5)
	var notes := [523.25, 659.25, 783.99]
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var ls := s - k * 0.09
			if ls > 0.0:
				v += sin(TAU * float(notes[k]) * ls) * exp(-ls * 6.0) * 0.6
				v += sin(TAU * float(notes[k]) * 2.0 * ls) * exp(-ls * 9.0) * 0.15
		out[i] = v
	return normalized(out, 0.7)


## Échec : deux notes qui descendent.
static func fail() -> PackedFloat32Array:
	var out := _buf(0.7)
	for i in out.size():
		var s := float(i) / RATE
		var f := 330.0 if s < 0.3 else 247.0
		var ls := s if s < 0.3 else s - 0.3
		out[i] = _lookup(_square(), f * s) * 0.5 * _env(ls, 0.38 if s >= 0.3 else 0.3, 0.01, 0.12)
	return normalized(out, 0.6)


## Fanfare de médaille : do-mi-sol-do, timbre de cuivre (dents de scie).
static func fanfare() -> PackedFloat32Array:
	var out := _buf(1.4)
	var notes := [261.63, 329.63, 392.0, 523.25]
	var starts := [0.0, 0.18, 0.36, 0.55]
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var ls: float = s - float(starts[k])
			var dur := 0.25 if k < 3 else 0.8
			if ls > 0.0 and ls < dur:
				v += _lookup(_saw(), float(notes[k]) * ls) * _env(ls, dur, 0.015, 0.1) * 0.6
		out[i] = v
	return normalized(out, 0.75)


## Pas sur le bitume : un souffle très court.
static func step() -> PackedFloat32Array:
	_rng.seed = 3
	var out := _buf(0.09)
	var lp := 0.0
	for i in out.size():
		var s := float(i) / RATE
		lp = lerpf(lp, _noise(), 0.25)
		out[i] = lp * exp(-s * 45.0) + sin(TAU * 120.0 * s) * 0.3 * exp(-s * 60.0)
	return normalized(out, 0.5)


## « Bip » de radio : un son de 1 kHz et un peu de grésillement (Kévin Radio prend la parole).
static func radio_blip() -> PackedFloat32Array:
	_rng.seed = 5
	var out := _buf(0.22)
	for i in out.size():
		var s := float(i) / RATE
		var v := sin(TAU * 1000.0 * s) * 0.5 * _env(s, 0.1, 0.004, 0.02) if s < 0.1 else 0.0
		v += _noise() * 0.12 * _env(s, 0.22, 0.01, 0.08)
		out[i] = v
	return normalized(out, 0.55)


## Cloche d'église : partiels inharmoniques qui s'éteignent lentement (440 Hz).
static func bell() -> PackedFloat32Array:
	var out := _buf(2.6)
	var partials := [[0.5, 1.0, 1.1], [1.0, 0.9, 1.4], [1.19, 0.6, 1.8], [1.56, 0.4, 2.4], [2.0, 0.5, 3.0], [2.51, 0.25, 4.0]]
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for p in partials:
			v += sin(TAU * 440.0 * float(p[0]) * s) * float(p[1]) * exp(-s * float(p[2]))
		out[i] = v * _env(s, 2.6, 0.003, 0.3)
	return normalized(out, 0.6)


## Vent : bruit passe-bas qui respire, boucle de 4 s (le bout est mélangé au début pour raccorder).
static func wind_loop() -> PackedFloat32Array:
	_rng.seed = 21
	var n := int(4.0 * RATE)
	var raw := PackedFloat32Array()
	raw.resize(n)
	var lp := 0.0
	for i in n:
		lp = lerpf(lp, _noise(), 0.04)
		raw[i] = lp
	var out := PackedFloat32Array()
	out.resize(n)
	var xf := int(0.5 * RATE)               # fondu enchaîné de 0,5 s pour une boucle sans couture
	for i in n:
		var s := float(i) / RATE
		var swell := 0.7 + 0.3 * sin(TAU * 0.25 * s)
		var v := raw[i]
		if i < xf:
			var k := float(i) / xf
			v = raw[i] * k + raw[n - xf + i] * (1.0 - k)
		out[i] = v * swell
	return normalized(out, 0.35)


## Oiseau : trois pépiements en glissando.
static func bird() -> PackedFloat32Array:
	var out := _buf(0.6)
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for k in 3:
			var ls := s - k * 0.17
			if ls > 0.0 and ls < 0.1:
				var f := 3200.0 + 900.0 * ls / 0.1 + 250.0 * k
				v += sin(TAU * f * ls) * sin(PI * ls / 0.1) * 0.6
		out[i] = v
	return normalized(out, 0.4)


# --- Musique : « Valse du Pommier » (Radio Pommiers) ------------------------------------------------
# Composition originale en la mineur, valse musette à 132 pulsations par minute : basse sur le
# premier temps, accords plaqués sur les deux autres, mélodie à l'anche double (deux anches
# désaccordées pour l'effet « musette »).

const BPM := 132.0
const BEAT := 60.0 / BPM
const BARS := 8

# midi : 69 = la4. -1 = silence. Chaque entrée : [note, durée en temps]
const MELODY := [
	[69, 1.5], [72, 0.5], [76, 1.0],        # mesure 1 : la do mi
	[74, 1.5], [77, 0.5], [81, 1.0],        # mesure 2 : ré fa la
	[80, 1.5], [76, 0.5], [74, 1.0],        # mesure 3 : sol# mi ré
	[72, 2.0], [-1, 1.0],                   # mesure 4 : do (repos)
	[76, 1.5], [77, 0.5], [76, 1.0],        # mesure 5
	[74, 1.5], [72, 0.5], [74, 1.0],        # mesure 6
	[71, 1.5], [68, 0.5], [71, 1.0],        # mesure 7 : si sol# si
	[69, 3.0],                              # mesure 8 : la
]
# Basse et accord par mesure : [fondamentale midi, [notes de l'accord]]
const CHORDS := [
	[45, [60, 64, 69]], [50, [62, 65, 69]], [52, [59, 64, 68]], [45, [60, 64, 69]],
	[45, [60, 64, 69]], [50, [62, 65, 69]], [52, [59, 64, 68]], [45, [60, 64, 69]],
]


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


## Ajoute une note d'anche à `out` à partir de `start` (s) pendant `dur` (s).
static func _note(out: PackedFloat32Array, midi: int, start: float, dur: float, gain: float, detune := 0.006) -> void:
	var t := _reed()
	var f1 := _hz(midi)
	var f2 := f1 * (1.0 + detune)
	var i0 := int(start * RATE)
	var n := int(dur * RATE)
	var p1 := 0.0
	var p2 := 0.0
	for k in n:
		var idx := i0 + k
		if idx >= out.size():
			break
		p1 += f1 / RATE
		p2 += f2 / RATE
		var s := float(k) / RATE
		out[idx] += (_lookup(t, p1) + _lookup(t, p2)) * 0.5 * gain * _env(s, dur, 0.02, 0.07)


static func music_length() -> float:
	return BARS * 3.0 * BEAT


static func music_pommier() -> PackedFloat32Array:
	var out := _buf(music_length())
	# Mélodie
	var beat_pos := 0.0
	for m in MELODY:
		var dur: float = float(m[1]) * BEAT
		if int(m[0]) >= 0:
			_note(out, int(m[0]), beat_pos * BEAT, dur * 0.95, 0.5)
		beat_pos += float(m[1])
	# Accompagnement : basse (temps 1), accord (temps 2 et 3).
	for bar in BARS:
		var c: Array = CHORDS[bar]
		var t0 := bar * 3.0 * BEAT
		_note(out, int(c[0]), t0, BEAT * 0.8, 0.45, 0.002)
		for beat in [1, 2]:
			for nn in c[1]:
				_note(out, int(nn) - 12, t0 + beat * BEAT, BEAT * 0.6, 0.12, 0.004)
	return normalized(out, 0.8)


# --- Playlists de la battle de sono (mission 03) ------------------------------------------------------
# Trois boucles originales à 120 pulsations par minute (1 temps = 0,5 s), 16 temps (8 s). Les coups de
# grosse caisse tombent exactement sur les temps : le beat que le joueur doit suivre s'entend.

const TRACK_BPM := 120.0
const TRACK_BEATS := 16
const TRACK_IDS := ["musette_remix", "techno_foraine", "tube_ete_2003"]


static func BEAT_T() -> float:
	return 60.0 / TRACK_BPM


static func track_length() -> float:
	return TRACK_BEATS * 60.0 / TRACK_BPM


static func _kick(out: PackedFloat32Array, t0: float, gain := 0.9) -> void:
	var i0 := int(t0 * RATE)
	for k in int(0.22 * RATE):
		if i0 + k >= out.size():
			break
		var s := float(k) / RATE
		var f := 48.0 + 90.0 * exp(-s * 28.0)
		out[i0 + k] += sin(TAU * f * s) * exp(-s * 12.0) * gain


static func _hat(out: PackedFloat32Array, t0: float, gain := 0.25) -> void:
	var i0 := int(t0 * RATE)
	for k in int(0.05 * RATE):
		if i0 + k >= out.size():
			break
		out[i0 + k] += _noise() * exp(-float(k) / RATE * 70.0) * gain


static func _clap(out: PackedFloat32Array, t0: float, gain := 0.5) -> void:
	var i0 := int(t0 * RATE)
	for k in int(0.16 * RATE):
		if i0 + k >= out.size():
			break
		var s := float(k) / RATE
		out[i0 + k] += _noise() * (exp(-s * 40.0) + 0.6 * exp(-maxf(s - 0.02, 0.0) * 40.0)) * gain


## Boucle de 8 s d'une playlist : « musette_remix », « techno_foraine » ou « tube_ete_2003 ».
static func track(id: String) -> PackedFloat32Array:
	_rng.seed = 303
	var beat := 60.0 / TRACK_BPM
	var out := _buf(track_length())
	for b in TRACK_BEATS:
		var t0 := b * beat
		match id:
			"musette_remix":
				_kick(out, t0, 0.7)
				if b % 2 == 1:
					_hat(out, t0 + beat * 0.5, 0.18)
				# Accordéon : accord la mineur / ré mineur / mi majeur, deux temps sur quatre.
				var chord: Array = [[57, 60, 64], [62, 65, 69], [56, 59, 64], [57, 60, 64]][b / 4]
				if b % 2 == 0:
					for n in chord:
						_note(out, int(n), t0, beat * 0.9, 0.16, 0.005)
				_note(out, int(chord[0]) - 12, t0, beat * 0.45, 0.3, 0.002)
			"techno_foraine":
				_kick(out, t0, 1.0)
				_hat(out, t0 + beat * 0.5, 0.3)
				if b % 4 == 3:
					_hat(out, t0 + beat * 0.25, 0.2)
				_note(out, [33, 33, 36, 31][b / 4], t0 + beat * 0.5, beat * 0.4, 0.3, 0.012)
			"tube_ete_2003":
				_kick(out, t0, 0.6)
				if b % 2 == 1:
					_clap(out, t0, 0.4)
				var arp := [69, 72, 76, 72, 67, 71, 74, 71, 65, 69, 72, 69, 67, 71, 74, 71]
				_note(out, int(arp[b]) + 12, t0, beat * 0.9, 0.2, 0.004)
				_note(out, int(arp[b]) + 12, t0 + beat * 0.5, beat * 0.4, 0.1, 0.004)
	return normalized(out, 0.85)



# --- Méchoui de la Saint-Jean (mission 04) ----------------------------------------------------------------------------

## Aboiement : deux « ouaf » brefs, un timbre rauque (anche grave + bruit).
static func bark() -> PackedFloat32Array:
	_rng.seed = 404
	var out := _buf(0.55)
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		for start in [0.0, 0.26]:
			var ls: float = s - float(start)
			if ls > 0.0 and ls < 0.2:
				var f := 420.0 - 700.0 * ls
				v += (_lookup(_reed(), f * ls) * 0.8 + _noise() * 0.35) * _env(ls, 0.2, 0.005, 0.12)
		out[i] = v
	return normalized(out, 0.8)


## Crépitement de braises : bruit haché, fort au départ puis décroissant.
static func sizzle() -> PackedFloat32Array:
	_rng.seed = 405
	var out := _buf(0.45)
	for i in out.size():
		var s := float(i) / RATE
		var crack := 1.0 if _rng.randf() < 0.04 else 0.25
		out[i] = _noise() * crack * exp(-s * 6.0)
	return normalized(out, 0.7)


## Feu d'artifice : sifflement montant puis éclatement et pluie d'étincelles.
static func firework() -> PackedFloat32Array:
	_rng.seed = 406
	var out := _buf(1.6)
	var ph := 0.0
	for i in out.size():
		var s := float(i) / RATE
		var v := 0.0
		if s < 0.55:
			ph += (500.0 + 2600.0 * s) / RATE
			v += sin(TAU * ph) * 0.35 * (0.3 + s)
		if s >= 0.55:
			var ls := s - 0.55
			v += _noise() * exp(-ls * 7.0) * 0.9
			v += sin(TAU * 70.0 * ls) * exp(-ls * 9.0) * 0.8
			if _rng.randf() < 0.012 * exp(-ls * 1.6):
				v += _noise() * 0.8
		out[i] = v
	return normalized(out, 0.85)
