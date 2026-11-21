class_name MissionM04
extends MissionBase
## Mission 04 « Le méchoui de la Saint-Jean » (agent 05) : un agneau à la broche pour huit convives.
##
## Déroulé (missions/m04_mechoui_saint_jean.json) : rapporter l'agneau, la broche et le charbon (4 min) ; tenir le feu
## dans la bonne plage pendant que l'agneau cuit (60 s) en chassant les chiens errants ; servir huit assiettes à quatre
## tables ; allumer le bûcher de la Saint-Jean (feu d'artifice). Tout l'état vit côté serveur (`_sync`).

const MISSION_FILE := "res://assets/missions/m04_mechoui_saint_jean.json"
const SYNC_PERIOD := 0.2
const ITEMS_STEP := "gather"
const ITEMS := ["agneau", "broche", "charbon"]
const ITEM_NAMES := {"agneau": "l'agneau de la ferme", "broche": "la broche de Tonton Gégé", "charbon": "le sac de charbon"}
const ITEM_POI := {"agneau": "item_agneau", "broche": "item_broche", "charbon": "item_charbon"}
const NEAR := {"item": 3.5, "station": 4.5, "table": 3.5, "shoo": 3.5, "pyre": 4.5, "post": 4.0}
const HEAT_START := 0.5
const HEAT_DECAY := 0.07                           # par seconde : il faut attiser environ toutes les 1,4 s
const PUMP_COOLDOWN := 0.25
const COLD := 0.3                                  # sous ce seuil : la viande ne cuit plus
const BURN_RATE := 0.04                            # par seconde au-dessus du seuil de brûlure
const LUKEWARM_RATE := 0.35                        # vitesse de cuisson entre « froid » et la bande idéale
const DOG_SPEED := 3.2
const DOG_FLEE_SPEED := 5.5
const DOG_START := 26.0                            # m : distance d'où les chiens arrivent
const DOG_STEAL := 1.5
const KEVIN_REACTION := 0.3                        # s : délai avant que Kévin chasse un chien à portée
const PLATES := 8
const SETUP_TIME := 240.0
const SERVE_TIME := 150.0
const START_HOUR := 19.0
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
const TABLE_LOCAL := [Vector3(-6.0, 0, 9.0), Vector3(6.0, 0, 9.0), Vector3(-6.0, 0, 15.0), Vector3(6.0, 0, 15.0)]
const KEVIN_RANGE := 6.0                           # m
const DOG_ANGLES := [0.9, -0.9, 2.1, -2.1, 0.0]

# --- Paramètres lus dans le JSON ---
var mission_id := "m04_mechoui_saint_jean"
var band := Vector2(0.45, 0.72)
var cook_sec := 60.0
var burn_above := 0.85
var pump_gain := 0.1
var dogs_solo := 3
var dogs_coop := 5
var steal_penalty := 0.1
var per_table := 2
var thresholds := {"gold": 85.0, "silver": 65.0, "bronze": 40.0}
var rewards := {}

# --- État répliqué ---
var items_taken: Array = []
var setup_left := SETUP_TIME
var heat := HEAT_START
var cook := 0.0
var burn := 0.0
var pumps := 0
var plates_left := 0
var served: Array = [0, 0, 0, 0]
var carry := {}                              # pair -> bool : porte une assiette
var serve_left := SERVE_TIME
var dogs: Array = []                         # {id, x, z, vx, vz, st: run|flee}
var dog_seq := 0
var stolen := 0
var shooed := 0
var lit := false
var satisfaction := 0.0
var result := ""                             # "" | "win" | "lose" | "late" | "burnt"
var medal := ""

var rng := RandomNumberGenerator.new()
var zones := {}
var facings := {}
var item_pos := {}
var day_night: DayNight
var _ground: Callable
var _dog_queue: Array = []
var _dog_timers := {}
var _pump_cd := 0.0
var _spots := {}
var _item_nodes := {}
var _table_nodes := {}
var _table_plates := {}
var _dog_nodes := {}
var _spit_node: Node3D
var _spit_key := ""
var _flames_node: Node3D
var _pyre_flames: Node3D
var _pyre_light: OmniLight3D
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _clock := 0.0


func _ready() -> void:
	title = "Le méchoui de la Saint-Jean"
	step = ITEMS_STEP
	rng.seed = 20260104
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		band = Vector2(float(m.fire.bandMin), float(m.fire.bandMax))
		cook_sec = float(m.fire.cookSec)
		burn_above = float(m.fire.burnAbove)
		pump_gain = float(m.fire.pumpGain)
		dogs_solo = int(m.dogs.solo)
		dogs_coop = int(m.dogs.coop)
		steal_penalty = float(m.dogs.stealPenalty)
		per_table = int(m.guests.perTable)
		for st in m.steps:
			if st.id == "gather":
				setup_left = float(st.timeLimitSec)
		for k in ["gold", "silver", "bronze"]:
			thresholds[k] = float(m.medals[k].satisfaction)
		rewards = m.rewards


# --- Mise en place -------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	var info := {}
	for p in pois:
		info[p.id] = p
	for pair in [["place_fete", "fete"], ["bucher", "bucher"]]:
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
	_build_visuals.call_deferred()


func _build_visuals() -> void:
	var w := get_parent()
	for it in ITEMS:
		if not item_pos.has(it):
			continue
		var kit: PropKit = {"agneau": PropKit.lamb(), "broche": PropKit.spit(), "charbon": PropKit.charcoal()}[it]
		var n := kit.build()
		n.name = "Objet_" + it
		n.position = item_pos[it]
		if it == "broche":
			n.scale = Vector3.ONE * 0.5
		w.add_child(n)
		_item_nodes[it] = n
	for i in TABLE_LOCAL.size():
		_set_table(i, 0)
	_flames_node = PropKit.flames().build(false)
	_flames_node.name = "M4_Flammes"
	_flames_node.visible = false
	w.add_child(_flames_node)
	_pyre_flames = PropKit.flames().build(false)
	_pyre_flames.name = "M4_FlammesBucher"
	_pyre_flames.visible = false
	w.add_child(_pyre_flames)
	_pyre_light = OmniLight3D.new()
	_pyre_light.light_color = Color(1.0, 0.6, 0.25)
	_pyre_light.omni_range = 28.0
	_pyre_light.light_energy = 0.0
	w.add_child(_pyre_light)
	if zones.has("bucher"):
		_pyre_flames.position = zones.bucher
		_pyre_flames.scale = Vector3.ONE * 1.5
		_pyre_light.position = zones.bucher + Vector3(0, 3.5, 0)
	if zones.has("fete"):
		_flames_node.position = station() + Vector3(0, 0.55, 0)
		_flames_node.scale = Vector3.ONE * 0.3


func _front(zone: String, local: Vector3) -> Vector3:
	if not zones.has(zone):
		return Vector3.ZERO
	return zones[zone] + Basis(Vector3.UP, float(facings.get(zone, 0.0))) * local


## Le foyer : l'agneau tourne ici, les assiettes se prennent ici.
func station() -> Vector3:
	return _front("fete", Vector3(0, 0, 0.6))


func table_pos(i: int) -> Vector3:
	var key := "table_%d" % i
	if _spots.has(key):
		return _spots[key]
	var base := _front("fete", TABLE_LOCAL[i])
	if base == Vector3.ZERO:
		return base
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[key] = base
	return base


func _set_table(i: int, plates: int) -> void:
	var p := table_pos(i)
	if p == Vector3.ZERO:
		return
	if _table_nodes.has(i):
		(_table_nodes[i] as Node3D).queue_free()
	var n := PropKit.table_set(plates).build()
	n.name = "M4_Table_%d" % i
	n.position = Vector3(p.x, _ground.call(p.x, p.z) if _ground.is_valid() else p.y, p.z)
	n.rotation.y = float(facings.get("fete", 0.0))
	get_parent().add_child(n)
	_table_nodes[i] = n
	_table_plates[i] = plates


func companion_roles() -> Dictionary:
	return {ID_GEGE: "cuisinier", ID_GINETTE: "serveur", ID_KEVIN: "gardien"}


func look_target() -> Vector3:
	return station()


func companion_item(id: int) -> String:
	return {ID_KEVIN: "broche", ID_GINETTE: "agneau", ID_GEGE: "charbon"}.get(id, "")


func item_taken(it: String) -> bool:
	return it in items_taken


func spot(name: String) -> Vector3:
	if _spots.has(name):
		return _spots[name]
	var base := Vector3.ZERO
	match name:
		"grill":
			base = _front("fete", Vector3(-2.2, 0, 3.2))
		"garde":
			base = _front("fete", Vector3(1.8, 0, 2.6))
		"pass":
			base = _front("fete", Vector3(2.4, 0, 2.6))
		_:
			return Vector3.ZERO
	if base == Vector3.ZERO:
		return base
	var w := get_parent()
	if w and w.has_method("find_free_spawn"):
		base = w.find_free_spawn(base)
	_spots[name] = base
	return base


func _dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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


func is_carrying(peer: int) -> bool:
	return bool(carry.get(peer, false)) or bool(carry.get(str(peer), false))


# --- Interaction --------------------------------------------------------------------------------------------------------

func _dog_near(pos: Vector3) -> int:
	for d in dogs:
		if d.st == "run" and Vector2(pos.x - d.x, pos.z - d.z).length() < float(NEAR.shoo):
			return int(d.id)
	return -1


func _table_for(pos: Vector3) -> int:
	for i in TABLE_LOCAL.size():
		var p := table_pos(i)
		if p != Vector3.ZERO and _dist(pos, p) < float(NEAR.table) and int(served[i]) < per_table:
			return i
	return -1


func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"]:
		return {}
	match step:
		ITEMS_STEP:
			for it in ITEMS:
				if not item_taken(it) and item_pos.has(it) and _dist(pos, item_pos[it]) < float(NEAR.item):
					return {"kind": "item", "item": it, "label": "Prendre %s" % ITEM_NAMES[it]}
		"fire", "serve":
			if _dog_near(pos) >= 0:
				return {"kind": "shoo", "label": "Chasser le chien !"}
			var at_station := _dist(pos, station()) < float(NEAR.station)
			if step == "fire" and at_station:
				return {"kind": "pump", "label": "Attiser le feu (E répété) : gardez la flèche dans la zone ▒"}
			if step == "serve":
				if is_carrying(peer):
					var t := _table_for(pos)
					if t >= 0:
						return {"kind": "serve", "table": t, "label": "Servir la table %d (%d/%d assiettes)" % [t + 1, served[t], per_table]}
					return {"kind": "none", "label": "Portez l'assiette à une table qui attend"}
				if at_station and plates_left > 0:
					return {"kind": "take", "label": "Prendre une assiette de méchoui (%d restantes)" % plates_left}
		"bonfire":
			if zones.has("bucher") and _dist(pos, zones.bucher) < float(NEAR.pyre):
				return {"kind": "light", "label": "Allumer le bûcher de la Saint-Jean"}
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
		"pump":
			_pump(player.display_name)
		"shoo":
			_shoo(_dog_near(player.global_position), player.display_name)
		"take":
			plates_left -= 1
			carry[peer] = true
			_log("%s prend une assiette de méchoui." % player.display_name)
		"serve":
			_serve(peer, int(r.table), player.display_name)
		"light":
			_light(player.display_name)
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


# --- Matériel -------------------------------------------------------------------------------------------------------------

func _take_item(it: String, player: Player) -> void:
	if item_taken(it):
		return
	items_taken.append(it)
	_log("%s prend %s." % [player.display_name, ITEM_NAMES[it]])
	if items_taken.size() == ITEMS.size():
		_log("Tout est là : la broche est montée, le charbon rougeoie. Attisez, il faut tenir le feu !")
		step = "fire"
		heat = HEAT_START
		cook = 0.0
		burn = 0.0
		var n := dogs_coop if humans() > 1 else dogs_solo
		_dog_queue = []
		for i in n:
			_dog_queue.append(0.15 + 0.7 * float(i) / float(maxi(n - 1, 1)))


# --- Feu ------------------------------------------------------------------------------------------------------------------------------

func _pump(name: String) -> void:
	if _pump_cd > 0.0:
		return
	_pump_cd = PUMP_COOLDOWN
	heat = minf(heat + pump_gain, 1.0)
	pumps += 1


## Vitesse de cuisson pour une chaleur donnée (fonction pure, testée) : 1 dans la bande idéale, 0 en dessous de « froid ».
static func cook_rate(h: float, band_min: float) -> float:
	if h >= band_min:
		return 1.0
	if h >= COLD:
		return LUKEWARM_RATE
	return 0.0


func _tick_fire(delta: float) -> void:
	_pump_cd = maxf(_pump_cd - delta, 0.0)
	heat = maxf(heat - HEAT_DECAY * delta, 0.0)
	if at_post(ID_GEGE, "grill") and heat < band.x + 0.07:
		_pump("Gégé")
		_dirty = true
	cook = minf(cook + cook_rate(heat, band.x) * delta / cook_sec, 1.0)
	if heat > burn_above:
		burn = minf(burn + BURN_RATE * delta, 1.0)
		if burn >= 1.0:
			_fail("burnt", "L'agneau est carbonisé ! Le Comité des fêtes se rabat sur des chips.")
			return
	while not _dog_queue.is_empty() and cook >= float(_dog_queue[0]):
		_dog_queue.pop_front()
		_spawn_dog()
	if cook >= 1.0:
		_begin_serve()


func _begin_serve() -> void:
	step = "serve"
	plates_left = PLATES
	serve_left = SERVE_TIME
	served = [0, 0, 0, 0]
	carry = {}
	_log("L'agneau est doré ! Huit assiettes à servir aux quatre tables, vite !")


# --- Chiens ---------------------------------------------------------------------------------------------------------------------------

func _spawn_dog() -> void:
	var a: float = DOG_ANGLES[dog_seq % DOG_ANGLES.size()]
	var f := float(facings.get("fete", 0.0))
	var s := station()
	var dir := Vector2(sin(f + a), cos(f + a))
	var start := Vector2(s.x, s.z) + dir * DOG_START
	var v := -dir * DOG_SPEED
	dog_seq += 1
	dogs.append({"id": dog_seq, "x": start.x, "z": start.y, "vx": v.x, "vz": v.y, "st": "run", "t": 0.0})
	_log("Un chien errant flaire le méchoui !")
	bark("m04_dog_comes", 8.0)


func _shoo(id: int, name: String) -> void:
	for d in dogs:
		if int(d.id) == id and d.st == "run":
			_flee(d)
			shooed += 1
			_log("%s chasse le chien !" % name)
			bark("m04_dog_shooed", 8.0)
			return


func _flee(d: Dictionary) -> void:
	var s := station()
	var away := Vector2(float(d.x) - s.x, float(d.z) - s.z).normalized()
	d.st = "flee"
	d.t = 0.0
	d.vx = away.x * DOG_FLEE_SPEED
	d.vz = away.y * DOG_FLEE_SPEED


func _tick_dogs(delta: float) -> void:
	var s := station()
	var kevin := actor(ID_KEVIN)
	var keep := []
	for d in dogs:
		d.x += d.vx * delta
		d.z += d.vz * delta
		d.t += delta
		if d.st == "run":
			if Vector2(float(d.x) - s.x, float(d.z) - s.z).length() < DOG_STEAL:
				stolen += 1
				_log("Un chien file avec un gigot ! (%d/%d perdus)" % [stolen, 3])
				bark("m04_dog_stole", 8.0)
				_flee(d)
				_dirty = true
			elif kevin != null and at_post(ID_KEVIN, "garde") and Vector2(kevin.global_position.x - float(d.x), kevin.global_position.z - float(d.z)).length() < KEVIN_RANGE:
				_dog_timers[d.id] = float(_dog_timers.get(d.id, 0.0)) + delta
				if float(_dog_timers[d.id]) >= KEVIN_REACTION:
					_flee(d)
					shooed += 1
					_log("Kévin chasse le chien !")
					bark("m04_dog_shooed", 8.0)
					_dirty = true
		if d.st == "flee" and d.t > 3.0:
			continue
		keep.append(d)
	dogs = keep


# --- Service --------------------------------------------------------------------------------------------------------------------

func _serve(peer: int, table: int, name: String) -> void:
	if not is_carrying(peer):
		return
	carry.erase(peer)
	served[table] = int(served[table]) + 1
	_log("%s sert la table %d." % [name, table + 1])
	if _total_served() >= PLATES:
		_begin_bonfire("Les huit convives sont servis ! Il est temps d'allumer le bûcher.")


func _total_served() -> int:
	var n := 0
	for v in served:
		n += int(v)
	return n


func _begin_bonfire(text: String) -> void:
	step = "bonfire"
	carry = {}
	_log(text)


# --- Bûcher et bilan --------------------------------------------------------------------------------------------------------------

## Satisfaction du village de 0 à 100 (fonction pure, testée) : cuisson, convives servis, chiens.
static func satisfaction_of(burn_ratio: float, guests: int, guests_max: int, stolen_count: int) -> float:
	var quality := clampf(1.0 - burn_ratio, 0.0, 1.0)
	var fed := float(guests) / float(maxi(guests_max, 1))
	var dogs_ok := 1.0 - minf(float(stolen_count), 3.0) / 3.0
	return 100.0 * (0.4 * quality + 0.4 * fed + 0.2 * dogs_ok)


func medal_for(score: float) -> String:
	if score >= thresholds.gold:
		return "gold"
	if score >= thresholds.silver:
		return "silver"
	if score >= thresholds.bronze:
		return "bronze"
	return ""


func _light(name: String) -> void:
	lit = true
	satisfaction = satisfaction_of(burn, _total_served(), PLATES, stolen)
	medal = medal_for(satisfaction)
	result = "win" if medal != "" else "lose"
	step = "done"
	_log("%s allume le bûcher : le feu d'artifice éclate !" % name)
	if result == "win":
		var prog := get_node("/root/Progress")
		prog.complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
		_log("Satisfaction du village : %d %%. Médaille : %s." % [int(satisfaction), {"gold": "or", "silver": "argent", "bronze": "bronze"}[medal]])
	else:
		_log("Satisfaction du village : %d %%. Le Comité des fêtes fera mieux l'an prochain." % int(satisfaction))
	_mark()
	_push_state()


func _fail(why: String, text: String) -> void:
	result = why
	step = "failed"
	_log(text)
	_mark()
	_push_state()


# --- Boucle serveur --------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = START_HOUR
			_log("Veille de la Saint-Jean. Rapportez l'agneau, la broche et le charbon : 4 minutes !")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	match step:
		ITEMS_STEP:
			setup_left -= delta
			if setup_left <= 0.0:
				_fail("late", "Trop tard : les convives ont mangé des sandwiches.")
				return
		"fire":
			_tick_fire(delta)
		"serve":
			serve_left -= delta
			if serve_left <= 0.0 and step == "serve":
				_begin_bonfire("Le temps est écoulé : les derniers convives devront se contenter du fromage. Allumez le bûcher !")
	if step in ["fire", "serve"]:
		_tick_dogs(delta)
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD and (_dirty or step in ["fire", "serve", ITEMS_STEP]):
		_sync_t = 0.0
		_push_state()


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	if carry.has(peer):
		carry.erase(peer)
		plates_left += 1
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication -----------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "items": items_taken, "sl": setup_left, "heat": heat, "cook": cook,
		"burn": burn, "pumps": pumps, "pl": plates_left, "served": served, "carry": carry, "sv": serve_left, "dogs": dogs, "ds": dog_seq,
		"stolen": stolen, "shooed": shooed, "lit": lit, "sat": satisfaction, "result": result, "medal": medal, "messages": messages}


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
	heat = s.heat
	cook = s.cook
	burn = s.burn
	pumps = s.pumps
	plates_left = s.pl
	served = s.served
	carry = s.carry
	serve_left = s.sv
	dogs = s.dogs
	dog_seq = s.ds
	stolen = s.stolen
	shooed = s.shooed
	lit = s.lit
	satisfaction = s.sat
	result = s.result
	medal = s.medal
	messages = s.messages
	changed.emit()


# --- Sons --------------------------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"items": items_taken.size(), "pumps": pumps, "dogs": dog_seq, "stolen": stolen, "shooed": shooed, "served": _total_served(),
		"plates": plates_left, "lit": lit, "step": step}
	if _snd.is_empty():
		_snd = now
		return
	if now.items > _snd.items:
		Sfx.play("crate")
	if now.pumps > _snd.pumps:
		Sfx.play("sizzle")
	if now.dogs > _snd.dogs:
		Sfx.play("bark")
	if now.stolen > _snd.stolen:
		Sfx.play("fail")
	if now.shooed > _snd.shooed or now.served > _snd.served:
		Sfx.play("chime")
	if now.plates < _snd.plates and now.step == "serve":
		Sfx.play("crate")
	if now.lit and not _snd.lit:
		Sfx.play("firework")
		for delay in [0.9, 1.8]:
			get_tree().create_timer(delay).timeout.connect(func(): Sfx.play("firework"))
	if now.step != _snd.step:
		if now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


# --- Rendu (mêmes nœuds sur tous les pairs) ------------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	if not is_server():
		if step == ITEMS_STEP:
			setup_left = maxf(setup_left - delta, 0.0)
		elif step == "fire":
			heat = maxf(heat - HEAT_DECAY * delta, 0.0)
		elif step == "serve":
			serve_left = maxf(serve_left - delta, 0.0)
		for d in dogs:
			d.x += d.vx * delta
			d.z += d.vz * delta
	for it in _item_nodes:
		if is_instance_valid(_item_nodes[it]):
			_item_nodes[it].visible = not item_taken(it)
	_update_spit()
	_update_tables()
	_update_dogs()
	_update_fire()
	for c in companions():
		(c as Player).carrying = is_carrying((c as Player).peer_id)
	for p in (_players_root.get_children() if _players_root else []):
		if p is Player and not (p as Player).is_ai:
			(p as Player).carrying = is_carrying((p as Player).peer_id)


func _update_spit() -> void:
	if not zones.has("fete"):
		return
	var shown := step in ["fire", "serve", "bonfire", "done"]
	if _spit_node == null and shown:
		_spit_key = ""
	var key := "%d_%d" % [int(round(cook * 4.0)), int(round(burn * 3.0))]
	if shown and key != _spit_key:
		if _spit_node:
			_spit_node.queue_free()
		_spit_node = PropKit.spit(cook, burn).build()
		_spit_node.name = "M4_Broche"
		_spit_node.position = station() + Vector3(0, 0.25, 0)
		_spit_node.rotation.y = float(facings.get("fete", 0.0))
		get_parent().add_child(_spit_node)
		_spit_key = key
	if _spit_node:
		_spit_node.visible = shown


func _update_tables() -> void:
	for i in TABLE_LOCAL.size():
		var plates := int(served[i]) * 2
		if _table_plates.get(i, -1) != plates and _ground.is_valid():
			_set_table(i, plates)


func _update_dogs() -> void:
	var live := {}
	for d in dogs:
		live[int(d.id)] = d
		var n: Node3D = _dog_nodes.get(int(d.id))
		if n == null:
			n = PropKit.dog().build()
			n.name = "Chien_%d" % int(d.id)
			get_parent().add_child(n)
			_dog_nodes[int(d.id)] = n
		var gy: float = _ground.call(float(d.x), float(d.z)) if _ground.is_valid() else 0.0
		n.position = Vector3(float(d.x), gy + absf(sin(_clock * 12.0 + float(d.id))) * 0.08, float(d.z))
		n.rotation.y = atan2(float(d.vx), float(d.vz))
	for id in _dog_nodes.keys():
		if not live.has(id):
			(_dog_nodes[id] as Node3D).queue_free()
			_dog_nodes.erase(id)


func _update_fire() -> void:
	if _flames_node:
		_flames_node.visible = step in ["fire", "serve"] and heat > 0.12
		var f := 0.2 + heat * 0.35 + 0.03 * sin(_clock * 14.0)
		_flames_node.scale = Vector3(f, f * (1.0 + 0.1 * sin(_clock * 9.0)), f)
	if _pyre_flames:
		_pyre_flames.visible = lit
		_pyre_light.light_energy = (2.2 + 0.5 * sin(_clock * 11.0)) if lit else 0.0
		if lit:
			var f := 1.5 + 0.12 * sin(_clock * 13.0)
			_pyre_flames.scale = Vector3(f, f * 1.15, f)


# --- HUD ---------------------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		ITEMS_STEP:
			var missing: PackedStringArray = []
			for it in ITEMS:
				if not item_taken(it):
					missing.append(ITEM_NAMES[it])
			return "Rapportez le matériel du méchoui (%s) : %s." % [MissionBase.format_time(setup_left), ", ".join(missing)]
		"fire":
			return "Tenez le feu dans la zone ▒ en attisant (E répété) : trop froid, ça ne cuit pas ; trop chaud, ça brûle. Chassez les chiens !"
		"serve":
			return "Servez les huit assiettes (%s) : prenez-les au foyer, portez-les aux tables." % MissionBase.format_time(serve_left)
		"bonfire":
			return "Allumez le bûcher de la Saint-Jean (près de la lueur rouge)."
		"done":
			return "Fête terminée."
		"failed":
			return "Fête ratée."
	return ""


func heat_bar() -> String:
	var n := 20
	var idx := int(round(clampf(heat, 0.0, 1.0) * float(n - 1)))
	var a := int(round(band.x * float(n - 1)))
	var b := int(round(band.y * float(n - 1)))
	var c := int(round(burn_above * float(n - 1)))
	var s := ""
	for i in n:
		if i == idx:
			s += "█"
		elif i >= a and i <= b:
			s += "▒"
		elif i > c:
			s += "▲"
		else:
			s += "·"
	return "[" + s + "]"


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step in ["fire", "serve"]:
		lines.append("Feu %s   Cuisson %d %%   Brûlé %d %%" % [heat_bar(), int(cook * 100.0), int(burn * 100.0)])
	if step == "serve":
		lines.append("Assiettes au foyer : %d   ·   Servies : %d/%d   ·   Tables : %s" % [plates_left, _total_served(), PLATES, " ".join(served.map(func(v): return "%d/%d" % [v, per_table]))])
	if step in ["fire", "serve", "bonfire"]:
		lines.append("Chiens chassés : %d   ·   Gigots volés : %d" % [shooed, stolen])
	if step == "done" or step == "failed":
		lines.append("Satisfaction du village : %d %%   ·   convives servis %d/%d" % [int(satisfaction), _total_served(), PLATES])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	var it := companion_item(c.peer_id)
	if step == ITEMS_STEP and it != "" and not item_taken(it):
		return "va chercher %s" % ITEM_NAMES[it]
	match role:
		"cuisinier":
			return "tient le feu à la bonne température" if at_post(c.peer_id, "grill") else "gagne le foyer"
		"serveur":
			return "porte les assiettes aux tables" if step == "serve" else "attend l'agneau doré"
		"gardien":
			return "chasse les chiens" if at_post(c.peer_id, "garde") else "prend position"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Fête réussie" if result == "win" else "Fête médiocre", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return {"burnt": "Agneau carbonisé", "late": "Trop tard"}.get(result, "Fête ratée")
	return ""
