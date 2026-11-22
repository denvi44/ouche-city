class_name MissionM03
extends MissionBase
## Mission 03 « Battle de sono » (agent 05) : le lotissement des Pommiers contre le Clos Fleuri.
##
## Déroulé (missions/m03_battle_sono.json) : rassembler caisson, rallonge et groupe électrogène (5 min) ;
## trois manches de rythme (la dernière avec le « lâcher de basses ») ; la 2e est troublée par les sabotages
## du rival ; quand la nuisance atteint 70 %, appel aux gendarmes (trois réponses) ; à 100 %, la sono est saisie.
## Tout l'état vit côté serveur ; les clients reçoivent `_sync` et prolongent l'horloge entre deux envois.

const MISSION_FILE := "res://assets/missions/m03_battle_sono.json"
const SYNC_PERIOD := 0.25
const BEAT := 0.5                                 # s : 120 pulsations par minute (Synth.TRACK_BPM)
const STAGE_RADIUS := 3.8                         # m : « sur la scène » (estrade de 7 × 3,6 m autour du repère)
const COUNT_TIME := 3.0                           # 6 temps avant le premier : la boucle musicale reste alignée
const ROUND_BEATS := [32, 40, 40]
const PERFECT := 0.09                             # s d'écart au temps toléré : « parfait »
const GOOD := 0.22
const POINTS := {"perfect": 3, "good": 2}
## Flèches du rythme : 0 gauche, 1 bas, 2 haut, 3 droite. La 1re manche n'en utilise que 2, la 2e 3, la dernière les 4.
const ARROW_SETS := [[0, 3], [0, 2, 3], [0, 1, 2, 3]]
const ARROW_NAMES := ["←", "↓", "↑", "→"]
const DROP_BEATS := 8                             # dernier « lâcher de basses » : points doublés
const RIVAL_RATIO := [0.38, 0.45, 0.52]           # part du maximum que le Clos Fleuri atteint à la fin de la manche
const RIVAL_AUDIENCE := ["jeunes", "tous", "anciens"]
const PLAYLISTS := ["musette_remix", "techno_foraine", "tube_ete_2003"]
const PLAYLIST_NAMES := {"musette_remix": "Musette remix", "techno_foraine": "Techno foraine", "tube_ete_2003": "Tube de l'été 2003"}
const AUDIENCE := {"musette_remix": "anciens", "techno_foraine": "jeunes", "tube_ete_2003": "tous"}
const COUNTER_BONUS := 1.2                        # jouer pour le public que le rival ne vise pas
const ITEMS_STEP := "setup"
const ITEMS := ["caisson", "rallonge", "groupe"]
const ITEM_NAMES := {"caisson": "le caisson de la Fusée", "rallonge": "la rallonge de Ginette", "groupe": "le groupe électrogène"}
const ITEM_POI := {"caisson": "item_caisson", "rallonge": "item_rallonge", "groupe": "item_groupe"}
const ITEM_COLOR := {"caisson": Color(0.85, 0.25, 0.3), "rallonge": Color(0.95, 0.75, 0.2), "groupe": Color(0.35, 0.65, 0.4)}
const NEAR := {"deck": 14.0, "item": 3.5, "spot": 5.0, "post": 4.0}
const PICK_TIME := 10.0
const PICK_FIRST := 20.0                          # la première manche : le temps de lire comment jouer
const BREAK_TIME := 5.0
const POLICE_TIME := 12.0
const SABOTAGE_TIME := 6.0
const MUTE_TIME := 4.0
const USB_TIME := 6.0
const NUISANCE_RATE := 0.011                      # par seconde de musique
const NUISANCE_HIT := 0.002                       # par temps réussi
const NUISANCE_DECAY := 0.004
const VIDEUR_BONUS := 0.08                        # part du maximum ajoutée par Ginette aux portes
const SABOTEUR_CUT := 0.12                        # part du maximum retirée au rival par Kévin
const SETUP_TIME := 300.0
const START_HOUR := 19.5
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
# Repère de la scène : +Z = devant (côté rue), les postes sont tous devant, à portée de la sono.
const SAB_SPOTS := {"unplug": Vector3(3.5, 0.0, 3.5), "usb_accordeon": Vector3(-3.5, 0.0, 3.5), "poules": Vector3(0.0, 0.0, 6.0)}
const SAB_NAMES := {"unplug": "Le rival débranche la rallonge !", "usb_accordeon": "Le rival glisse une clé USB d'accordéon !", "poules": "Le rival lâche des poules sur la scène !"}
const SAB_DEFEND := {"unplug": "Rebrancher la rallonge", "usb_accordeon": "Retirer la clé USB", "poules": "Rattraper les poules"}

# --- Paramètres lus dans le JSON ---
var mission_id := "m03_battle_sono"
var police_at := 0.7
var seizure_at := 1.0
var solo_rate := 0.75
var lemoine_after := 90.0
var rival_attempts := {"solo": 2, "coop": 4}
var rewards := {}
var nuis_mult := {"musette_remix": 1.0, "techno_foraine": 1.3, "tube_ete_2003": 1.0}

# --- État répliqué ---
var items_taken: Array = []
var setup_left := SETUP_TIME
var round_idx := 0                          # 0..2
var round_state := "pick"                   # pick | count | play | police | result
var pick_left := PICK_TIME
var count_left := 0.0
var play_t := 0.0
var break_left := 0.0
var playlist := "musette_remix"
var score_p := 0.0
var score_r := 0.0
var results: Array = []                     # par manche : {won, p, r, playlist}
var nuisance := 0.0
var police_done := false
var police_visit := false
var police_left := 0.0
var lemoine_done := false
var menu := ""                              # "" | "playlist" | "police"
var menu_options: Array = []
var menu_peer := 0
var last_hit := {"q": "", "k": -1}          # dernier temps joué : {q: perfect|good|miss, k}
var hits := {"perfect": 0, "good": 0, "miss": 0}
var sab := {"kind": "", "left": 0.0}
var mute_left := 0.0
var usb_left := 0.0
var sab_blocked := 0
var sab_hits := 0
var result := ""                            # "" | "win" | "lose" | "seized" | "late"
var medal := ""
var test_roll := -1.0

var rng := RandomNumberGenerator.new()
var zones := {}                             # camp, rival -> Vector3
var facings := {}                           # camp, rival -> cap de la scène (rad)
var item_pos := {}                          # item -> Vector3
var day_night: DayNight
var _sab_queue: Array = []                  # temps (en battements) des tentatives restantes
var _hit_set := {}
var _arrow_cache := {}
var _lemoine_t := 0.0
var _spots := {}
var _item_nodes := {}
var _stage_camp: Node
var _stage_rival: Node
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _log_text: Array = []


func _ready() -> void:
	title = "Battle de sono"
	step = "setup"
	rng.seed = 20260103
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		police_at = float(m.nuisance.policeCallAt)
		seizure_at = float(m.nuisance.seizureAt)
		solo_rate = float(m.nuisance.soloRateMultiplier)
		lemoine_after = float(m.nuisance.lemoineArrivalSec)
		for pl in m.playlists:
			nuis_mult[pl.id] = float(pl.get("nuisanceMultiplier", 1.0))
		for st in m.steps:
			if st.id == "setup":
				setup_left = float(st.timeLimitSec)
			if st.id == "round_sabotage":
				rival_attempts = st.rivalAttempts
		rewards = m.rewards


# --- Mise en place -------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	var info := {}
	for p in pois:
		info[p.id] = p
	for pair in [["camp_pommiers", "camp"], ["camp_clos_fleuri", "rival"]]:
		if info.has(pair[0]):
			var x := float(info[pair[0]].position[0])
			var z := float(info[pair[0]].position[1])
			zones[pair[1]] = Vector3(x, ground.call(x, z), z)
			facings[pair[1]] = float(info[pair[0]].get("facing", 0.0))
	for it in ITEMS:
		if info.has(ITEM_POI[it]):
			var x := float(info[ITEM_POI[it]].position[0])
			var z := float(info[ITEM_POI[it]].position[1])
			item_pos[it] = Vector3(x, ground.call(x, z), z)
			_make_item(w, it, item_pos[it])
	_bind_stages.call_deferred()


func _make_item(world: Node, it: String, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Objet_" + it
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.7, 0.7) if it != "rallonge" else Vector3(0.6, 0.4, 0.6)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/toon.gdshader")
	mat.set_shader_parameter("couleur", ITEM_COLOR[it])
	mesh.material = mat
	mi.mesh = mesh
	mi.position = pos + Vector3(0, 0.45, 0)
	world.add_child.call_deferred(mi)
	_item_nodes[it] = mi


func _bind_stages() -> void:
	var w := get_parent()
	_stage_camp = w.find_child("Lieu_camp_pommiers", true, false)
	_stage_rival = w.find_child("Lieu_camp_clos_fleuri", true, false)


func companion_roles() -> Dictionary:
	return {ID_GEGE: "electricien", ID_GINETTE: "videur", ID_KEVIN: "saboteur"}


func look_target() -> Vector3:
	return zones.get("camp", Vector3.ZERO)


func item_taken(it: String) -> bool:
	return it in items_taken


## Objet de départ d'un compagnon (Kévin : le caisson de sa Fusée…).
func companion_item(id: int) -> String:
	return {ID_KEVIN: "caisson", ID_GINETTE: "rallonge", ID_GEGE: "groupe"}.get(id, "")


## Emplacement d'attente (calculé à la demande, physique prête).
func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"groupe":
			base = _front("camp", Vector3(-6.0, 0, 4.5))
		"videur":
			base = _front("camp", Vector3(6.0, 0, 4.5))
		"clos":
			base = _front("rival", Vector3(4.0, 0, 4.5))
		"sab_unplug", "sab_usb_accordeon", "sab_poules":
			base = _front("camp", SAB_SPOTS.get(name.trim_prefix("sab_"), Vector3.ZERO))
		"item_caisson", "item_rallonge", "item_groupe":
			return item_pos.get(name.trim_prefix("item_"), Vector3.ZERO)
		_:
			return Vector3.ZERO
	if base == Vector3.ZERO:
		return Vector3.ZERO
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[name] = base
	return base


## Point exprimé dans le repère de la scène (`local`, +Z devant) converti en monde.
func _front(zone: String, local: Vector3) -> Vector3:
	if not zones.has(zone):
		return Vector3.ZERO
	return zones[zone] + Basis(Vector3.UP, float(facings.get(zone, 0.0))) * local


func _dist(pos: Vector3, p: Vector3) -> float:
	return Vector2(pos.x - p.x, pos.z - p.z).length()


## Un compagnon (ou joueur) est-il à son poste ?
func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and _dist(a.global_position, s) < float(NEAR.post)


func humans() -> int:
	var n := 0
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				n += 1
	return maxi(n, 1)


# --- Interaction --------------------------------------------------------------------------------------------

func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	if menu != "" and (menu_peer == 0 or menu_peer == peer):
		return {"kind": "none", "label": "Choisissez avec les touches 1 à %d" % menu_options.size()}
	if step == "setup":
		for it in ITEMS:
			if not item_taken(it) and item_pos.has(it) and _dist(pos, item_pos[it]) < float(NEAR.item):
				return {"kind": "item", "item": it, "label": "Prendre %s" % ITEM_NAMES[it]}
		return {}
	if step == "round" and round_state == "play" and zones.has("camp"):
		if sab.kind != "":
			var sp := spot("sab_" + str(sab.kind))
			if sp != Vector3.ZERO and _dist(pos, sp) < float(NEAR.spot):
				return {"kind": "defend", "label": "%s !" % SAB_DEFEND[sab.kind]}
		if _dist(pos, zones.camp) < float(NEAR.deck):
			return {"kind": "none", "label": "Flèches ← ↓ ↑ → : appuyez sur celle qui arrive, quand elle touche la ligne"}
		return {"kind": "none", "label": "Retournez à la sono (à moins de %d m)" % int(NEAR.deck)}
	return {}


func interact(peer: int, allowed: Array = []) -> void:
	if not is_server():
		return
	var player := actor(peer) as Player
	if player == null:
		return
	var r := resolve(peer, player.global_position)
	var kind: String = r.get("kind", "")
	if kind == "" or kind == "none" or (not allowed.is_empty() and not (kind in allowed)):
		return
	match kind:
		"item":
			_take_item(r.item, player)
		"defend":
			_defend(player.display_name)
	_mark()


func request_interact() -> void:
	if is_server():
		interact(multiplayer.get_unique_id())
	else:
		_request_interact.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_interact() -> void:
	if is_server():
		interact(multiplayer.get_remote_sender_id())


func request_choice(option: String) -> void:
	if is_server():
		choose_for(multiplayer.get_unique_id(), option)
	else:
		_request_choice.rpc_id(1, option)


@rpc("any_peer", "call_remote", "reliable")
func _request_choice(option: String) -> void:
	if is_server():
		choose_for(multiplayer.get_remote_sender_id(), option)


# --- Rassemblement du matériel ---------------------------------------------------------------------------------

func _take_item(it: String, player: Player) -> void:
	if item_taken(it):
		return
	items_taken.append(it)
	_log("%s prend %s." % [player.display_name, ITEM_NAMES[it]])
	if items_taken.size() == ITEMS.size():
		_log("Tout le matériel est là : la sono des Pommiers est montée. À vous la première manche !")
		_begin_round(0)


# --- Manches ------------------------------------------------------------------------------------------------------------

func rounds_total() -> int:
	return ROUND_BEATS.size()


func beats_in(r: int) -> int:
	return int(ROUND_BEATS[r])


func round_duration() -> float:
	return beats_in(round_idx) * BEAT


func _begin_round(r: int) -> void:
	step = "round"
	round_idx = r
	round_state = "pick"
	pick_left = PICK_FIRST if r == 0 else PICK_TIME
	play_t = 0.0
	score_p = 0.0
	score_r = 0.0
	_hit_set = {}
	sab = {"kind": "", "left": 0.0}
	mute_left = 0.0
	usb_left = 0.0
	_sab_queue = []
	last_hit = {"q": "", "k": -1}
	_open_menu("playlist")
	_log("Manche %d/%d : le Clos Fleuri vise le public « %s »." % [r + 1, rounds_total(), RIVAL_AUDIENCE[r]])


func _open_menu(kind: String) -> void:
	menu = kind
	menu_options = []
	var hs := _first_human()
	menu_peer = hs
	if kind == "playlist":
		for id in PLAYLISTS:
			var extra := ""
			if nuis_mult[id] > 1.0:
				extra = ", +%d %% de bruit" % int(round((nuis_mult[id] - 1.0) * 100.0))
			elif id == "tube_ete_2003":
				extra = ", public ×0,7"
			var pour: String = {"anciens": "plaît aux anciens", "jeunes": "plaît aux jeunes", "tous": "plaît à tout le monde"}[AUDIENCE[id]]
			menu_options.append("%s : %s%s" % [PLAYLIST_NAMES[id], pour, extra])
	elif kind == "police":
		menu_options = ["Barbecue pour les gendarmes (−35 % de nuisance)", "Accuser le Clos Fleuri (50 % : −50 % de nuisance, sinon +15 %)", "Distribuer des merguez (−25 % de nuisance, la foule applaudit)"]


func _first_human() -> int:
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				return (p as Player).peer_id
	return 0


func choose_for(peer: int, option: String) -> void:
	if not is_server() or menu == "" or (menu_peer != 0 and menu_peer != peer) or not option.is_valid_int():
		return
	var idx := int(option) - 1
	if idx < 0 or idx >= menu_options.size():
		return
	if menu == "playlist":
		_choose_playlist(PLAYLISTS[idx])
	elif menu == "police":
		_choose_police(idx)
	_mark()


func _choose_playlist(id: String) -> void:
	playlist = id
	menu = ""
	menu_options = []
	menu_peer = 0
	round_state = "wait"          # le décompte ne part que lorsqu'un joueur est monté sur la scène
	count_left = COUNT_TIME
	_log("Playlist : %s. Montez sur la scène (repère « Votre sono ») : le rythme démarre dès que vous y êtes." % PLAYLIST_NAMES[id])
	if round_idx == 1:
		var n := int(rival_attempts.coop if humans() > 1 else rival_attempts.solo)
		for i in n:      # de 10 % à 60 % de la manche : la dernière tentative a le temps d'aboutir
			_sab_queue.append(float(beats_in(round_idx)) * (0.1 + 0.5 * float(i) / float(maxi(n - 1, 1))))


func _choose_police(idx: int) -> void:
	var roll := test_roll if test_roll >= 0.0 else rng.randf()
	match idx:
		0:
			nuisance -= 0.35
			_log("Barbecue : les gendarmes se resservent de merguez, la nuisance retombe.")
		1:
			if roll < 0.5:
				nuisance -= 0.5
				_log("Le Clos Fleuri est accusé à tort : les gendarmes filent chez eux.")
			else:
				nuisance += 0.15
				_log("Personne ne vous croit : « C'est bien chez vous que ça fait du bruit ! »")
		_:
			nuisance -= 0.25
			score_p += 3.0
			_log("Merguez pour tout le monde : la foule applaudit (+3 points).")
	nuisance = clampf(nuisance, 0.0, 1.0)
	menu = ""
	menu_options = []
	menu_peer = 0
	round_state = "play"


func _press(_peer: int, dir: int) -> void:
	if round_state != "play":
		return
	if mute_left > 0.0:
		_log("Le son est coupé : rebranchez la rallonge !")
		hits.miss += 1
		last_hit = {"q": "miss", "k": -1}
		return
	var k := int(round(play_t / BEAT))
	var err := absf(play_t - float(k) * BEAT)
	if k < 0 or k >= beats_in(round_idx) or err > GOOD or _hit_set.has(k) or dir != int(arrows()[k]):
		hits.miss += 1
		last_hit = {"q": "miss", "k": k}
		return
	var q := "perfect" if err <= PERFECT else "good"
	_hit_set[k] = true
	hits[q] += 1
	last_hit = {"q": q, "k": k}
	score_p += point_value(q, k, round_idx, playlist, usb_left > 0.0)
	nuisance += NUISANCE_HIT * _nuis_factor()


## Suite de flèches d'une manche (fonction pure, identique chez tous les pairs) : jamais plus de deux fois la même d'affilée.
static func arrow_sequence(r: int, n: int) -> Array:
	var g := RandomNumberGenerator.new()
	g.seed = 31000 + r * 97
	var set: Array = ARROW_SETS[clampi(r, 0, ARROW_SETS.size() - 1)]
	var out: Array = []
	for i in n:
		var d: int = set[g.randi() % set.size()]
		if out.size() >= 2 and out[-1] == d and out[-2] == d:
			d = set[(set.find(d) + 1) % set.size()]
		out.append(d)
	return out


func arrows(r: int = -1) -> Array:
	var rr := round_idx if r < 0 else r
	if not _arrow_cache.has(rr):
		_arrow_cache[rr] = arrow_sequence(rr, beats_in(rr))
	return _arrow_cache[rr]


## Flèche attendue au temps le plus proche (utile aux tests et au bot).
func current_arrow() -> int:
	var k := clampi(int(round(play_t / BEAT)), 0, beats_in(round_idx) - 1)
	return int(arrows()[k])


## Ce que l'écran doit tracer : null hors manche jouée.
func rhythm_view() -> Dictionary:
	if step != "round" or not (round_state in ["count", "play"]):
		return {}
	return {"t": play_t if round_state == "play" else -count_left, "arrows": arrows(), "last": last_hit, "beat": BEAT}


## Appelé par le joueur local (flèches du clavier ou croix directionnelle).
func request_arrow(dir: int) -> void:
	if is_server():
		press_arrow(multiplayer.get_unique_id(), dir)
	else:
		_request_arrow.rpc_id(1, dir)


@rpc("any_peer", "call_remote", "reliable")
func _request_arrow(dir: int) -> void:
	if is_server():
		press_arrow(multiplayer.get_remote_sender_id(), dir)


## Un appui de flèche, côté serveur : seulement près de la sono.
func press_arrow(peer: int, dir: int) -> void:
	if not is_server() or step != "round" or round_state != "play" or not zones.has("camp"):
		return
	var player := actor(peer) as Player
	if player == null or _dist(player.global_position, zones.camp) >= float(NEAR.deck):
		return
	_press(peer, dir)
	_mark()


## Valeur d'un temps réussi (fonction pure, testée) : qualité, rang du temps, manche, playlist, clé USB active.
static func point_value(q: String, k: int, r: int, pl: String, usb: bool) -> float:
	var v: float = POINTS[q]
	if r == ROUND_BEATS.size() - 1 and k >= int(ROUND_BEATS[r]) - DROP_BEATS:
		v *= 2.0
	var a: String = AUDIENCE[pl]
	if pl == "tube_ete_2003":
		v *= 0.7
	elif a != RIVAL_AUDIENCE[r] and a != "tous":
		v *= COUNTER_BONUS
	if usb:
		v *= 0.5
	return v


func max_points(r: int) -> float:
	var n := beats_in(r)
	var drops := DROP_BEATS if r == ROUND_BEATS.size() - 1 else 0
	return 3.0 * float(n + drops)


func rival_goal() -> float:
	var cut := SABOTEUR_CUT if at_post(ID_KEVIN, "clos") else 0.0
	return max_points(round_idx) * maxf(RIVAL_RATIO[round_idx] - cut, 0.0)


func _nuis_factor() -> float:
	return float(nuis_mult[playlist]) * (solo_rate if humans() == 1 else 1.0)


func _defend(name: String) -> void:
	if sab.kind == "":
		return
	sab_blocked += 1
	_log("%s déjoue le sabotage !" % name)
	bark("m03_sabotage_blocked", 10.0)
	sab = {"kind": "", "left": 0.0}


func _sabotage_lands() -> void:
	sab_hits += 1
	match str(sab.kind):
		"unplug":
			mute_left = MUTE_TIME
		"usb_accordeon":
			usb_left = USB_TIME
		"poules":
			score_p = maxf(score_p - 6.0, 0.0)
			nuisance += 0.05
	_log("Sabotage réussi : %s" % SAB_NAMES[sab.kind])
	bark("m03_sabotage_hit", 10.0)
	sab = {"kind": "", "left": 0.0}


func _tick_round(delta: float) -> void:
	match round_state:
		"pick":
			pick_left -= delta
			if pick_left <= 0.0 and menu == "playlist":
				_log("Pas de choix : musette remix par défaut.")
				_choose_playlist("musette_remix")
		"wait":
			if on_stage():
				round_state = "count"
				count_left = COUNT_TIME
				_log("Sur scène : le rythme démarre !")
				_mark()
		"count":
			count_left -= delta
			if count_left <= 0.0:
				round_state = "play"
				play_t = 0.0
		"play":
			_tick_play(delta)
		"police":
			police_left -= delta
			if police_left <= 0.0:
				nuisance = clampf(nuisance + 0.1, 0.0, 1.0)
				_log("Les gendarmes n'ont pas eu de réponse : ils notent le tapage (+10 %).")
				menu = ""
				menu_options = []
				menu_peer = 0
				round_state = "play"
				_mark()
		"result":
			break_left -= delta
			if break_left <= 0.0:
				if round_idx + 1 < rounds_total():
					_begin_round(round_idx + 1)
					_mark()
				else:
					_finish()


## Un joueur humain est-il sur l'estrade (à moins de STAGE_RADIUS du repère) ?
func on_stage() -> bool:
	if not zones.has("camp") or _players_root == null:
		return false
	for p in _players_root.get_children():
		if p is Player and not (p as Player).is_ai:
			var d: Vector3 = (p as Player).global_position - (zones.camp as Vector3)
			if Vector2(d.x, d.z).length() <= STAGE_RADIUS:
				return true
	return false


func _tick_play(delta: float) -> void:
	play_t += delta
	mute_left = maxf(mute_left - delta, 0.0)
	usb_left = maxf(usb_left - delta, 0.0)
	nuisance += NUISANCE_RATE * _nuis_factor() * delta
	_lemoine_t += delta
	if not lemoine_done and _lemoine_t >= lemoine_after:
		lemoine_done = true
		if at_post(ID_GINETTE, "videur"):
			_log("Lemoine, le voisin, débarque : Ginette le retient à la porte.")
			bark("m03_lemoine", 60.0)
		else:
			nuisance += 0.08
			_log("Lemoine, le voisin, débarque en robe de chambre (+8 % de nuisance).")
			bark("m03_lemoine", 60.0)
	# Sabotages du rival.
	if sab.kind != "":
		if str(sab.kind) == "unplug" and at_post(ID_GEGE, "groupe"):
			sab.left -= delta * 4.0        # Gégé, électricien, rebranche vite
			if sab.left <= SABOTAGE_TIME - 1.5:
				_defend("Gégé")
		else:
			sab.left -= delta
			if sab.left <= 0.0:
				_sabotage_lands()
		_mark()
	elif not _sab_queue.is_empty() and play_t >= float(_sab_queue[0]) * BEAT:
		_sab_queue.pop_front()
		var kinds := ["unplug", "usb_accordeon", "poules"]
		sab = {"kind": kinds[(sab_blocked + sab_hits) % 3], "left": SABOTAGE_TIME}
		_log(SAB_NAMES[sab.kind])
		_mark()
	score_r = rival_goal() * clampf(play_t / round_duration(), 0.0, 1.0)
	if not police_done and nuisance >= police_at and nuisance < seizure_at:
		police_done = true
		police_visit = true
		round_state = "police"
		police_left = POLICE_TIME
		_open_menu("police")
		_log("Les gendarmes arrivent (nuisance %d %%) !" % int(nuisance * 100.0))
		bark("m03_police", 60.0)
		_mark()
	elif play_t >= round_duration() + BEAT:
		_end_round()


func _end_round() -> void:
	var videur := VIDEUR_BONUS * max_points(round_idx) if at_post(ID_GINETTE, "videur") else 0.0
	score_p += videur
	score_r = rival_goal()
	var won := score_p >= score_r
	results.append({"won": won, "p": snappedf(score_p, 0.1), "r": snappedf(score_r, 0.1), "playlist": playlist})
	if videur > 0.0:
		_log("Ginette tient les portes : +%d points d'ambiance." % int(videur))
	_log("Manche %d : %s (%d à %d)." % [round_idx + 1, "gagnée" if won else "perdue", int(score_p), int(score_r)])
	round_state = "result"
	break_left = BREAK_TIME
	sab = {"kind": "", "left": 0.0}
	_mark()


func rounds_won() -> int:
	var n := 0
	for r in results:
		if r.won:
			n += 1
	return n


func _finish() -> void:
	var won := rounds_won()
	result = "win" if won >= 2 else "lose"
	if won == rounds_total() and not police_visit:
		medal = "gold"
	elif won == rounds_total():
		medal = "silver"
	elif won >= 2:
		medal = "bronze"
	else:
		medal = ""
	step = "done"
	if result == "win":
		_log("VICTOIRE ! Le Clos Fleuri range ses enceintes. %s" % {"gold": "Médaille d'or : pas un gendarme.", "silver": "Médaille d'argent.", "bronze": "Médaille de bronze."}[medal])
		var prog := get_node("/root/Progress")
		prog.complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	else:
		_log("Le Clos Fleuri l'emporte : demain, il faudra faire plus fort.")
	_mark()
	_push_state()


func _fail(why: String, text: String) -> void:
	result = why
	step = "failed"
	round_state = "result"
	menu = ""
	menu_options = []
	_log(text)
	_mark()
	_push_state()


# --- Boucle serveur ------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			_log("Samedi soir. Rassemblez le caisson, la rallonge et le groupe électrogène : 5 minutes !")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	if step == "setup":
		setup_left -= delta
		if setup_left <= 0.0:
			_fail("late", "Trop tard : la nuit tombe et le matériel n'est pas là. Le Clos Fleuri a la place.")
			return
	elif step == "round":
		if round_state in ["play", "count", "police"]:
			pass
		else:
			nuisance = maxf(nuisance - NUISANCE_DECAY * delta, 0.0)
		_tick_round(delta)
		if nuisance >= seizure_at and step == "round":
			_fail("seized", "Les gendarmes saisissent la sono ! Fin de la battle.")
			return
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD and (_dirty or step == "round" or step == "setup"):
		_sync_t = 0.0
		_push_state()


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	if menu_peer == peer:
		menu_peer = _first_human()
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication ------------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "items": items_taken, "sl": setup_left, "ri": round_idx,
		"rs": round_state, "pl": pick_left, "cl": count_left, "pt": play_t, "bl": break_left, "list": playlist,
		"sp": score_p, "sr": score_r, "res": results, "nu": nuisance, "pd": police_done, "pv": police_visit, "pol": police_left,
		"menu": menu, "mo": menu_options, "mp": menu_peer, "lh": last_hit, "hits": hits, "sab": sab, "mute": mute_left, "usb": usb_left,
		"sb": sab_blocked, "sh": sab_hits, "result": result, "medal": medal, "messages": messages}


func _push_state() -> void:
	_dirty = false
	var s := state()
	for id in Net.ready_peers():
		_sync.rpc_id(id, s)


func send_full_state(peer: int) -> void:
	if is_server():
		_sync.rpc_id(peer, state())


@rpc("authority", "call_remote", "reliable")
func _sync(s: Dictionary) -> void:
	step = s.step
	started = s.started
	elapsed = s.elapsed
	items_taken = s.items
	setup_left = s.sl
	round_idx = s.ri
	round_state = s.rs
	pick_left = s.pl
	count_left = s.cl
	play_t = s.pt
	break_left = s.bl
	playlist = s.list
	score_p = s.sp
	score_r = s.sr
	results = s.res
	nuisance = s.nu
	police_done = s.pd
	police_visit = s.pv
	police_left = s.pol
	menu = s.menu
	menu_options = s.mo
	menu_peer = s.mp
	last_hit = s.lh
	hits = s.hits
	sab = s.sab
	mute_left = s.mute
	usb_left = s.usb
	sab_blocked = s.sb
	sab_hits = s.sh
	result = s.result
	medal = s.medal
	messages = s.messages
	changed.emit()


# --- Sons et effets (mêmes déclencheurs sur tous les pairs) ----------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"items": items_taken.size(), "rs": round_state, "ri": round_idx, "step": step, "perfect": hits.perfect, "good": hits.good,
		"miss": hits.miss, "sab": str(sab.kind), "sh": sab_hits, "police": police_done, "won": rounds_won()}
	if _snd.is_empty():
		_snd = now
		return
	if now.items > _snd.items:
		Sfx.play("crate")
	if now.perfect > _snd.perfect:
		Sfx.play("chime")
	elif now.good > _snd.good:
		Sfx.play("crate")
	if now.sab != "" and now.sab != _snd.sab:
		Sfx.play("fail")
	if now.police and not _snd.police:
		Sfx.play("klaxon")
	if now.rs == "count" and (_snd.rs != "count" or now.ri != _snd.ri):
		Sfx.play_track(playlist)
	if _snd.rs in ["play", "police", "count"] and now.rs in ["result", "pick"]:
		Sfx.stop_track()
	if now.step != _snd.step:
		Sfx.stop_track()
		if now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _process(delta: float) -> void:
	_audio_events()
	if not is_server():
		match round_state:
			"count":
				count_left = maxf(count_left - delta, 0.0)
			"play":
				play_t += delta
		if step == "setup":
			setup_left = maxf(setup_left - delta, 0.0)
	for it in _item_nodes:
		if is_instance_valid(_item_nodes[it]):
			_item_nodes[it].visible = not item_taken(it)
	_pulse(_stage_camp, round_state == "play" and step == "round", 0.0)
	_pulse(_stage_rival, round_state == "play" and step == "round", 0.5)
	for c in companions():
		(c as Player).carrying = false


## Les enceintes pulsent sur le temps (déphasage 0,5 temps pour le rival).
func _pulse(stage: Node, on: bool, offset: float) -> void:
	if stage == null:
		return
	var s := 1.0
	if on:
		var phase := fposmod(play_t / BEAT + offset, 1.0)
		s = 1.0 + 0.18 * exp(-phase * 7.0)
	for n in ["HP_G", "HP_D"]:
		var hp := stage.get_node_or_null(n) as Node3D
		if hp:
			hp.scale = Vector3(s, s, s)


# --- HUD ------------------------------------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		"setup":
			var missing: PackedStringArray = []
			for it in ITEMS:
				if not item_taken(it):
					missing.append(ITEM_NAMES[it])
			return "Rassemblez le matériel avant la nuit (%s) : %s." % [MissionBase.format_time(setup_left), ", ".join(missing)]
		"round":
			match round_state:
				"pick":
					var best: String = {"jeunes": "anciens", "tous": "jeunes", "anciens": "jeunes"}[RIVAL_AUDIENCE[round_idx]]
					return "Manche %d/%d — choisissez la musique avec les touches 1, 2 ou 3 (%d s). Le Clos Fleuri joue pour les %s : visez plutôt les %s pour un bonus !" % [round_idx + 1, rounds_total(), int(ceil(pick_left)), RIVAL_AUDIENCE[round_idx], best]
				"wait":
					return "Manche %d — montez sur la scène (marqueur « Votre sono ») : le rythme démarre dès que vous y êtes. Flèches ← ↓ ↑ → pour jouer." % [round_idx + 1]
				"count":
					return "Manche %d — allez à la sono (marqueur « Votre sono ») et préparez-vous : appuyez sur la flèche qui arrive (← ↓ ↑ →) quand elle touche la ligne. Début dans %d…" % [round_idx + 1, int(ceil(count_left / BEAT)) if count_left > 0.0 else 0]
				"play":
					var extra := ""
					if sab.kind != "":
						extra = " — %s Courez à %s !" % [SAB_NAMES[sab.kind], SAB_DEFEND[sab.kind].to_lower()]
					return "Restez près de la sono et appuyez sur la flèche du clavier (← ↓ ↑ →) qui touche la ligne, à chaque coup de grosse caisse.%s" % extra
				"police":
					return "Les gendarmes sont là : répondez (touches 1 à 3), %d s !" % int(ceil(police_left))
				"result":
					return "Manche %d terminée. Prochaine manche dans %d s." % [round_idx + 1, int(ceil(break_left))]
		"done":
			return "Battle terminée."
		"failed":
			return "Battle perdue."
	return ""


## Curseur de rythme : il traverse la barre à chaque temps, le centre est le temps exact.
func beat_bar() -> String:
	var n := 21
	var half := n / 2
	var p := fposmod(play_t / BEAT + 0.5, 1.0) - 0.5          # -0.5 .. 0.5 autour du temps
	var cur := half + int(round(p * float(n - 1)))
	var perfect := int(round(PERFECT / BEAT * float(n - 1)))
	var good := int(round(GOOD / BEAT * float(n - 1)))
	var s := ""
	for i in n:
		var d := absi(i - half)
		if i == cur:
			s += "█"
		elif d <= perfect:
			s += "▓"
		elif d <= good:
			s += "▒"
		else:
			s += "·"
	return "[" + s + "]"


func nuisance_bar() -> String:
	var n := 20
	var f := int(round(clampf(nuisance, 0.0, 1.0) * n))
	return "[" + "█".repeat(f) + "·".repeat(n - f) + "] %d %%" % int(nuisance * 100.0)


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step == "round" and round_idx == 0 and (round_state in ["pick", "wait", "count"] or (round_state == "play" and play_t < 40.0)):
		lines.append("Comment jouer :")
		lines.append("  1. Choisissez la musique (touches 1, 2, 3) : chacune plaît à un public. Jouez pour celui que le Clos Fleuri vise le moins.")
		lines.append("  2. Restez à moins de %d m de la sono (marqueur « Votre sono »)." % int(NEAR.deck))
		lines.append("  3. Des flèches défilent vers la ligne : appuyez sur la même flèche du clavier (← ↓ ↑ →) quand elle la touche. Plus c'est juste, plus la foule se rallie.")
		lines.append("  4. Le bruit fait monter la Nuisance : à %d %%, les gendarmes arrivent." % int(police_at * 100.0))
	if step == "round":
		lines.append("Manche %d/%d  ·  Pommiers %d  —  Clos Fleuri %d  ·  Playlist : %s" % [round_idx + 1, rounds_total(), int(score_p), int(score_r), PLAYLIST_NAMES.get(playlist, "")])
		lines.append("Nuisance %s%s" % [nuisance_bar(), "  (gendarmes à %d %%)" % int(police_at * 100.0) if not police_done else ""])
		if round_state == "play":
			lines.append("Rythme : %s" % {"perfect": "PARFAIT !", "good": "bien", "miss": "raté"}.get(str(last_hit.q), "suivez les flèches"))
			if mute_left > 0.0:
				lines.append("Son coupé : %.0f s" % ceil(mute_left))
			if usb_left > 0.0:
				lines.append("Clé USB d'accordéon : points ÷2 pendant %.0f s" % ceil(usb_left))
	if step in ["done", "failed"] and not results.is_empty():
		for i in results.size():
			lines.append("Manche %d : %s — Pommiers %d, Clos Fleuri %d (%s)" % [i + 1, "gagnée" if results[i].won else "perdue", int(results[i].p), int(results[i].r), PLAYLIST_NAMES.get(results[i].playlist, "")])
		lines.append("Gendarmes : %s   ·   Sabotages déjoués : %d, subis : %d" % ["venus" if police_visit else "jamais venus", sab_blocked, sab_hits])
	if menu != "":
		lines.append("Menu :")
		for i in menu_options.size():
			lines.append("  [%d] %s" % [i + 1, menu_options[i]])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_line(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	var it := companion_item(c.peer_id)
	if step == "setup" and it != "" and not item_taken(it):
		return "va chercher %s" % ITEM_NAMES[it]
	match role:
		"electricien":
			return "veille sur le groupe (rebranche vite)" if at_post(c.peer_id, "groupe") else "gagne le groupe électrogène"
		"videur":
			return "tient les portes (+ambiance, retient Lemoine)" if at_post(c.peer_id, "videur") else "gagne les portes"
		"saboteur":
			return "sabote la sono du Clos Fleuri" if at_post(c.peer_id, "clos") else "file chez les rivaux"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Victoire" if result == "win" else "Défaite", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return {"seized": "Sono saisie", "late": "Trop tard"}.get(result, "Battle perdue")
	if step == "round" and round_state == "count":
		return str(int(ceil(count_left / BEAT)) if count_left > 0.0 else 0)
	return ""


func hud_gauges() -> Array:
	var out := []
	if step == "setup":
		out.append(gauge("temps", "Matériel", setup_left / 300.0, C_GOAL, MissionBase.format_time(setup_left), {"low_is_bad": true}))
		out.append(gauge("objets", "Objets", float(items_taken.size()) / float(ITEMS.size()), C_OK, "%d / %d" % [items_taken.size(), ITEMS.size()]))
	if step == "round":
		out.append(gauge("foule", "Pommiers", score_p / maxf(max_points(round_idx), 1.0), C_OK, "%d  contre  %d" % [int(score_p), int(score_r)], {"marker": clampf(score_r / maxf(max_points(round_idx), 1.0), 0.0, 1.0)}))
		out.append(gauge("nuisance", "Nuisance", nuisance, C_DANGER, "%d %%" % int(nuisance * 100.0), {"danger": true, "zone": Vector2(police_at, 1.0)}))
	return out


func hud_markers() -> Array:
	var out := []
	if step == "setup":
		for it in ITEMS:                       # un objet à la fois, dans l'ordre
			if not item_taken(it) and item_pos.has(it):
				out.append(marker(item_pos[it], ITEM_NAMES[it].capitalize(), C_ITEM))
				break
	elif step == "round" and zones.has("camp"):
		out.append(marker(zones.camp, "Votre sono", C_GOAL))
		if sab.kind != "":
			var sp := spot("sab_" + str(sab.kind))
			if sp != Vector3.ZERO:
				out.append(marker(sp, SAB_DEFEND[sab.kind], C_DANGER, true))
	return out