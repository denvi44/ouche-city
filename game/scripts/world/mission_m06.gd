class_name MissionM06
extends MissionBase
## Mission 06 « Les courses de 8 h » (agent 05) : faire ses six courses au Panier d'Ouche… à 2 km/h.
##
## Tous les acheteurs marchent à 2 à l'heure (plafond de vitesse sur le joueur) et lisent les étiquettes (3 s immobile).
## Les clients pressés, eux, arrivent toutes les 14 s sur des parcours fixes dans les allées ; bloqués derrière vous, ils
## perdent patience (incident à 100 %). « Après vous ! » les laisse passer. Mme Hubert vous retient pour une causette.
## À la caisse : compter la monnaie (4 pièces, curseur lent). Le gérant raccompagne dehors au quatrième incident.
## Simulation à autorité serveur dans le repère local du magasin (x le long de la façade, +z = devant) ; les clients
## sont en état pur, répliqués à 5 Hz et prolongés par les clients entre deux envois.

const MISSION_FILE := "res://assets/missions/m06_courses_de_8h.json"
const SYNC_PERIOD := 0.2
const ITEMS := ["baguette", "camembert", "lait", "cidre", "palets", "litiere"]
const ITEM_NAMES := {"baguette": "une baguette bien cuite", "camembert": "un camembert (coulant)", "lait": "du lait demi-écrémé", "cidre": "du cidre brut",
	"palets": "des palets bretons", "litiere": "de la litière pour le chat"}
const ITEMS_STEP := "shop"
const WALK_MS := 2.0 / 3.6                          # 2 km/h
const NEAR := {"item": 1.7, "pay": 2.4, "exit": 2.6, "chat": 2.0, "pass": 3.6}
const START_MIN := 480.0                            # 8 h 00
const COIN_ZONE := Vector2(0.38, 0.62)
const MINI_SPEED := 1.7
const PASS_COOLDOWN := 6.0
const PASS_TIME := 3.5
const STEP_ASIDE := 1.2
const CHAT_TIME := 8.0
const CHAT_CUT := 1.5
const ID_GEGE := -1
const ID_GINETTE := -2
const ID_KEVIN := -4
const POST := 3.0
# Parcours des clients pressés (repère local) ; (x, z).
const ROUTES := [
	[Vector2(0, 11), Vector2(0, 6.5), Vector2(10.5, 4.0), Vector2(10.5, -1.0), Vector2(10.5, -6.6), Vector2(-10.5, -6.6), Vector2(-10.5, 0.25), Vector2(10.5, 0.25),
		Vector2(10.5, 3.5), Vector2(8.5, 4.3), Vector2(0, 6.5), Vector2(0, 11), Vector2(0, 18)],
	[Vector2(0, 11), Vector2(0, 6.5), Vector2(-10.5, 3.5), Vector2(-10.5, -3.0), Vector2(10.5, -3.0), Vector2(10.5, 0.25), Vector2(10.5, 3.5), Vector2(4.5, 4.3),
		Vector2(0, 6.5), Vector2(0, 11), Vector2(0, 18)],
]
## Trajets des compagnons pour prendre un article, après la porte : points intermédiaires puis position de l'article.
const ITEM_ROUTES := {
	"baguette": [Vector2(10.5, 3.5), Vector2(10.5, -6.6)],
	"camembert": [Vector2(-10.5, 3.5), Vector2(-10.5, -6.6)],
	"lait": [Vector2(-10.5, 3.5), Vector2(-10.5, -6.6)],
	"cidre": [Vector2(-10.5, 3.5), Vector2(-10.5, -3.0)],
	"palets": [Vector2(-10.5, 3.5), Vector2(-10.5, 0.25)],
	"litiere": [],
}
const CHAT_SPOT := Vector2(-3.0, 0.25)
const PAY_SPOT := Vector2(8.5, 4.6)
const DOOR_SPOT := Vector2(0, 9.2)

var mission_id := "m06_courses_de_8h"
var secs_per_min := 6.0
var deadline := {"gold": 530.0, "silver": 540.0, "bronze": 570.0, "fail": 570.0}
var reading_sec := 3.0
var customers_solo := 6
var customers_coop := 9
var first_at := 3.0
var every := 14.0
var cust_speed := 1.5
var patience_sec := 12.0
var max_incidents := 4
var penalty_sec := 6.0
var gold_incidents := 1
var coins_needed := 4
var coin_fail_penalty := 8.0
var rewards := {}

# --- État répliqué ---
var items_got: Array = []
var reading := {}                          # {peer, item, t} ; vide = personne ne lit
var chat_left := 0.0
var chat_done := false
var coins := 0
var mini_t := 0.0
var mini_fails := 0
var customers: Array = []                  # {id, x, z, vx, vz, imp, wp, route, hold}
var cust_seq := 0
var incidents := 0
var politeness := 0
var blocked_total := 0.0
var penalty := 0.0
var stepaside_left := 0.0
var pass_left := 0.0
var result := ""                           # "" | "win" | "late" | "evicted"
var medal := ""
var clock_min := START_MIN

var rng := RandomNumberGenerator.new()
var origin := Vector3.ZERO                 # centre du magasin (monde)
var facing := 0.0
var zone_ok := false
var day_night: DayNight
var _ground: Callable
var _spawn_t := 0.0
var _pass_cd := 0.0
var _sync_t := 0.0
var _dirty := true
var _snd := {}
var _cust_nodes := {}
var _cashier: Node3D
var _hubert: Node3D
var _clock := 0.0


func _ready() -> void:
	title = "Les courses de 8 h"
	step = ITEMS_STEP
	rng.seed = 20260106
	var m = CityBuilder.read_json(MISSION_FILE)
	if m is Dictionary:
		mission_id = m.id
		title = m.title
		secs_per_min = float(m.clock.secondsPerGameMinute)
		for k in ["gold", "silver", "bronze", "fail"]:
			deadline[k] = _hhmm(str(m.clock[k]))
		reading_sec = float(m.reading.sec)
		customers_solo = int(m.customers.solo)
		customers_coop = int(m.customers.coop)
		first_at = float(m.customers.firstAtSec)
		every = float(m.customers.everySec)
		cust_speed = float(m.customers.speed)
		patience_sec = float(m.customers.patienceSec)
		max_incidents = int(m.incidents.maxBeforeEviction)
		penalty_sec = float(m.incidents.penaltySec)
		gold_incidents = int(m.incidents.goldMaxIncidents)
		coins_needed = int(m.payment.coins)
		coin_fail_penalty = float(m.payment.failPenaltySec)
		rewards = m.rewards


static func _hhmm(s: String) -> float:
	var p := s.split(":")
	return float(p[0]) * 60.0 + float(p[1])


# --- Mise en place ----------------------------------------------------------------------------------------------

func setup(pois: Array, ground: Callable, _vehicle: Vehicle, players_root: Node3D) -> void:
	_ground = ground
	_players_root = players_root
	var w := get_parent()
	day_night = w.get("day_night")
	for p in pois:
		if p.id == "supermarche":
			var x := float(p.position[0])
			var z := float(p.position[1])
			facing = float(p.get("facing", 0.0))
			var base := Vector3(x, ground.call(x, z), z)
			origin = Vector3(x, base.y + Supermarket.lift_for(ground, base, facing), z)
			zone_ok = true
	_build_visuals.call_deferred()


func to_world(l: Vector2) -> Vector3:
	var v := Basis(Vector3.UP, facing) * Vector3(l.x, 0, l.y)
	return Vector3(origin.x + v.x, origin.y + 0.12, origin.z + v.z)


func to_local(p: Vector3) -> Vector2:
	var d := Vector3(p.x - origin.x, 0, p.z - origin.z)
	var v := Basis(Vector3.UP, -facing) * d
	return Vector2(v.x, v.z)


func item_local(it: String) -> Vector2:
	var v: Vector3 = Supermarket.shopping_spots()[it]
	return Vector2(v.x, v.z)


func item_world(it: String) -> Vector3:
	return to_world(item_local(it))


func _build_visuals() -> void:
	var w := get_parent()
	if not zone_ok:
		return
	# La caissière Josette et Mme Hubert (immobiles).
	_cashier = CharacterModel.make(Color(0.88, 0.2, 0.2), Color(0.2, 0.2, 0.26), Color(0.15, 0.17, 0.25), {"hair": Color(0.55, 0.3, 0.15), "hair_style": "bun", "headgear": "none", "apron": Color(0.95, 0.95, 0.95)})
	_cashier.name = "Josette"
	_cashier.pose_override = {"speed": 0.0}
	w.add_child(_cashier)
	_cashier.global_position = to_world(Vector2(8.5, 7.0))
	_cashier.rotation.y = facing + PI
	_hubert = CharacterModel.make(Color(0.5, 0.65, 0.4), Color(0.4, 0.35, 0.3), Color(0.75, 0.7, 0.8), {"hair": Color(0.8, 0.8, 0.85), "hair_style": "bun", "headgear": "none", "glasses": true, "scarf": Color(0.85, 0.6, 0.3)})
	_hubert.name = "MmeHubert"
	_hubert.pose_override = {"speed": 0.0}
	w.add_child(_hubert)
	_hubert.global_position = to_world(CHAT_SPOT + Vector2(1.0, 0))
	_hubert.rotation.y = facing - PI / 2.0
	var label := Label3D.new()
	label.text = "Mme Hubert"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.4
	label.font_size = 40
	label.pixel_size = 0.004
	label.outline_size = 10
	_hubert.add_child(label)


func companion_roles() -> Dictionary:
	return {ID_GINETTE: "bavarde", ID_GEGE: "caddie", ID_KEVIN: "chauffeur"}


func look_target() -> Vector3:
	return to_world(Vector2(0, 0))


## Articles que prend un compagnon (en plus du joueur) : Gégé le cidre et les palets.
func companion_items(id: int) -> Array:
	return ["palets", "cidre"] if id == ID_GEGE else []


func spot(name: String) -> Vector3:
	match name:
		"chat":
			return to_world(CHAT_SPOT + Vector2(-0.8, 0))
		"parking":
			return to_world(Vector2(6.0, 13.0))
	return Vector3.ZERO


func at_post(id: int, name: String) -> bool:
	var a := actor(id)
	var s := spot(name)
	return a != null and s != Vector3.ZERO and Vector2(a.global_position.x - s.x, a.global_position.z - s.z).length() < POST


## Trajet (points monde) de la porte à l'article, puis l'article lui-même.
func route_to(it: String) -> Array:
	var pts := [to_world(Vector2(0, 9.5)), to_world(Vector2(0, 6.5))]
	for p in ITEM_ROUTES[it]:
		pts.append(to_world(p))
	pts.append(item_world(it))
	return pts


func route_to_chat() -> Array:
	return [to_world(Vector2(0, 9.5)), to_world(Vector2(0, 6.5)), to_world(Vector2(-10.5, 3.5)), to_world(Vector2(-10.5, 0.25)), spot("chat")]


func humans() -> int:
	var n := 0
	if _players_root:
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai:
				n += 1
	return maxi(n, 1)


# --- Horloge ------------------------------------------------------------------------------------------------------

func game_minutes() -> float:
	return START_MIN + (elapsed + penalty) / secs_per_min


static func clock_text(minutes: float) -> String:
	return "%d h %02d" % [int(minutes / 60.0), int(fmod(minutes, 60.0))]


func medal_for(minutes: float, incs: int) -> String:
	if minutes <= deadline.gold and incs <= gold_incidents:
		return "gold"
	if minutes <= deadline.silver:
		return "silver"
	if minutes <= deadline.bronze:
		return "bronze"
	return ""


## Plafond de vitesse d'un acheteur (m/s) : 2 km/h, nul pendant la lecture d'une étiquette, la causette, le pas de côté et le paiement.
func cap_for(peer: int) -> float:
	if step in ["done", "failed"]:
		return INF
	if (not reading.is_empty() and int(reading.peer) == peer) or chat_left > 0.0 or stepaside_left > 0.0 or step == "pay":
		return 0.0
	return WALK_MS


# --- Interaction -------------------------------------------------------------------------------------------------------------

func _dist_l(pos: Vector3, l: Vector2) -> float:
	return to_local(pos).distance_to(l)


func blocked_near(pos: Vector3) -> bool:
	for c in customers:
		if float(c.imp) > 0.15 and Vector2(c.x, c.z).distance_to(to_local(pos)) < float(NEAR.pass):
			return true
	return false


func resolve(peer: int, pos: Vector3) -> Dictionary:
	if step in ["done", "failed"] or not zone_ok:
		return {}
	var here := to_local(pos)
	if not reading.is_empty():
		return {"kind": "none", "label": "Vous lisez l'étiquette… (%d %%)" % int(float(reading.t) / reading_sec * 100.0)} if int(reading.peer) == peer else {}
	if chat_left > 0.0:
		return {"kind": "cut", "label": "Mme Hubert vous raconte sa hanche (E : couper court, poliment)"}
	if step == ITEMS_STEP:
		for it in ITEMS:
			if not (it in items_got) and here.distance_to(item_local(it)) < float(NEAR.item):
				return {"kind": "read", "item": it, "label": "Lire l'étiquette et prendre %s" % ITEM_NAMES[it]}
		if _pass_cd <= 0.0 and blocked_near(pos):
			return {"kind": "pass", "label": "« Après vous ! » : laisser passer la file"}
		if items_got.size() == ITEMS.size() and here.distance_to(PAY_SPOT) < float(NEAR.pay):
			return {"kind": "pay", "label": "Passer en caisse : compter la monnaie"}
		return {}
	if step == "pay":
		return {"kind": "press", "label": "Appuyez quand le curseur est dans la zone ▒ (pièce %d/%d)" % [coins + 1, coins_needed]}
	if step == "exit":
		if _pass_cd <= 0.0 and blocked_near(pos):
			return {"kind": "pass", "label": "« Après vous ! » : laisser passer la file"}
		if here.distance_to(DOOR_SPOT) < float(NEAR.exit):
			return {"kind": "leave", "label": "Sortir du magasin avec vos courses"}
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
		"read":
			reading = {"peer": peer, "item": r.item, "t": 0.0}
			_log("%s lit l'étiquette : « Sans conservateurs… »" % player.display_name)
		"cut":
			chat_left = maxf(chat_left - CHAT_CUT, 0.0)
			if chat_left <= 0.0:
				_log("« Bon, faut que j'y aille ! » Mme Hubert est vexée pour trois minutes.")
				bark("m06_chat_cut", 20.0)
		"pass":
			_let_pass(player.display_name)
		"pay":
			step = "pay"
			coins = 0
			mini_t = 0.0
			_log("Caisse 2 : Josette vous sourit. Il vous faut 17,43 € en petite monnaie.")
		"press":
			_press()
		"leave":
			_finish()
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


func _let_pass(name: String) -> void:
	_pass_cd = PASS_COOLDOWN
	pass_left = PASS_TIME
	stepaside_left = STEP_ASIDE
	politeness += 1
	for c in customers:
		if Vector2(c.x, c.z).distance_to(Vector2(0, 0)) < 40.0:
			c.imp = maxf(float(c.imp) - 0.5, 0.0)
	_log("%s : « Après vous, je vous en prie ! » La file s'écoule." % name)
	bark("m06_pass", 8.0)


# --- Paiement : compter la monnaie -------------------------------------------------------------------------------------------------

func mini_pos() -> float:
	return 0.5 + 0.5 * sin(mini_t * MINI_SPEED * PI)


func _press() -> void:
	var p := mini_pos()
	if p >= COIN_ZONE.x and p <= COIN_ZONE.y:
		coins += 1
		_log("Pièce %d/%d : « Voilà, voilà. »" % [coins, coins_needed])
		if coins >= coins_needed:
			step = "exit"
			_log("Payé ! Josette tamponne le ticket. Dirigez-vous vers la sortie.")
	else:
		mini_fails += 1
		penalty += coin_fail_penalty
		_log("« Ah non, pas cette pièce-là… » Elle fouille encore dans son porte-monnaie (+%d s)." % int(coin_fail_penalty))
		bark("m06_coin_fail", 10.0)


# --- Clients pressés (serveur) ------------------------------------------------------------------------------------------------------

func _spawn_customer() -> void:
	cust_seq += 1
	var route: int = (cust_seq - 1) % ROUTES.size()
	var start: Vector2 = ROUTES[route][0]
	customers.append({"id": cust_seq, "x": start.x, "z": start.y, "vx": 0.0, "vz": 0.0, "imp": 0.0, "wp": 1, "route": route, "hold": 0.0})


func _blockers_for(c: Dictionary, dir: Vector2) -> bool:
	var here := Vector2(c.x, c.z)
	var others: Array = []
	if pass_left <= 0.0 and _players_root:
		for p in _players_root.get_children():
			# Les humains bloquent toujours ; un compagnon à l'arrêt (Ginette qui papote) se laisse contourner.
			if p is Player and (not (p as Player).is_ai or Vector2((p as Player).velocity.x, (p as Player).velocity.z).length() > 0.3):
				others.append(to_local((p as Player).global_position))
	for o in customers:
		if int(o.id) != int(c.id):
			var op := Vector2(o.x, o.z)
			# Un client plus loin sur le même parcours (ou plus ancien) bloque celui qui arrive derrière lui.
			if int(o.id) < int(c.id):
				others.append(op)
	for b in others:
		var d: Vector2 = b - here
		var ahead := d.dot(dir)
		if ahead > 0.0 and ahead < 1.7 and absf(d.cross(dir)) < 0.8:
			return true
	return false


func _tick_customers(delta: float) -> void:
	var max_c := customers_coop if humans() > 1 else customers_solo
	_spawn_t += delta
	if cust_seq < max_c and _spawn_t >= first_at + float(cust_seq) * every:
		_spawn_customer()
	var keep := []
	for c in customers:
		var route: Array = ROUTES[int(c.route)]
		var here := Vector2(c.x, c.z)
		if int(c.wp) >= route.size():
			continue
		var target: Vector2 = route[int(c.wp)]
		var d := target - here
		var dir := d.normalized() if d.length() > 0.01 else Vector2.ZERO
		if float(c.hold) > 0.0:
			c.hold = float(c.hold) - delta
			c.vx = 0.0
			c.vz = 0.0
			keep.append(c)
			continue
		var blocked := _blockers_for(c, dir)
		if blocked:
			c.vx = 0.0
			c.vz = 0.0
			c.imp = float(c.imp) + delta / patience_sec
			blocked_total += delta
			if float(c.imp) >= 1.0:
				_incident(c)
		else:
			c.imp = maxf(float(c.imp) - 0.15 * delta, 0.0)
			c.x = here.x + dir.x * cust_speed * delta
			c.z = here.y + dir.y * cust_speed * delta
			c.vx = dir.x * cust_speed
			c.vz = dir.y * cust_speed
			if here.distance_to(target) < 0.5:
				c.wp = int(c.wp) + 1
				if target.distance_to(Vector2(8.5, 4.3)) < 0.1 or target.distance_to(Vector2(4.5, 4.3)) < 0.1:
					c.hold = 3.0          # passage en caisse
		keep.append(c)
	customers = keep


func _incident(c: Dictionary) -> void:
	incidents += 1
	penalty += penalty_sec
	c.imp = 0.4
	_log("Un client : « Dites donc, vous allez bouger ?! » (incident %d/%d, +%d s)" % [incidents, max_incidents, int(penalty_sec)])
	bark("m06_incident", 8.0)
	_dirty = true
	if incidents >= max_incidents:
		_fail("evicted", "M. Lebrun, le gérant, vous raccompagne gentiment à la porte : « Revenez à dix heures, Madame. »")


# --- Bilan --------------------------------------------------------------------------------------------------------------------------------

func _finish() -> void:
	clock_min = game_minutes()
	medal = medal_for(clock_min, incidents)
	result = "win" if medal != "" else "late"
	step = "done"
	if result == "win":
		_log("Sortie du magasin à %s : %s. %d incident(s), %d « Après vous »." % [clock_text(clock_min), {"gold": "médaille d'or", "silver": "médaille d'argent", "bronze": "médaille de bronze"}[medal], incidents, politeness])
		get_node("/root/Progress").complete(mission_id, medal, rewards.get("reputation", {}), rewards.get("unlocks", []), [])
	else:
		_log("Il est %s quand vous sortez : le magasin a fermé pour la pause de midi." % clock_text(clock_min))
	_mark()
	_push_state()


func _fail(why: String, text: String) -> void:
	result = why
	step = "failed"
	clock_min = game_minutes()
	_log(text)
	_mark()
	_push_state()


# --- Boucle serveur --------------------------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not is_server():
		return
	if not started:
		if _players_root and _players_root.get_child_count() > 0 and zone_ok:
			started = true
			get_node("/root/Progress").start(mission_id)
			if day_night:
				day_night.hour = 8.0
				day_night.running = false
			_teleport_to_entrance()
			_log("Huit heures. Le Panier d'Ouche ouvre ses portes. Six articles sur la liste, deux kilomètres à l'heure : prenez votre temps.")
			_mark()
		return
	if step in ["done", "failed"]:
		return
	elapsed += delta
	_pass_cd = maxf(_pass_cd - delta, 0.0)
	pass_left = maxf(pass_left - delta, 0.0)
	stepaside_left = maxf(stepaside_left - delta, 0.0)
	clock_min = game_minutes()
	if day_night:
		day_night.hour = 8.0 + (clock_min - START_MIN) / 60.0
	if step == "pay":
		mini_t += delta
	# Lecture d'une étiquette.
	if not reading.is_empty():
		reading.t = float(reading.t) + delta
		if float(reading.t) >= reading_sec:
			var it: String = reading.item
			if not (it in items_got):
				items_got.append(it)
				_log("Dans le cabas : %s (%d/%d)." % [ITEM_NAMES[it], items_got.size(), ITEMS.size()])
				bark("m06_item", 20.0)
			reading = {}
			_mark()
	# Causette de Mme Hubert : seulement si Ginette ne l'occupe pas déjà.
	if chat_left > 0.0:
		chat_left = maxf(chat_left - delta, 0.0)
		if chat_left <= 0.0:
			_mark()
	elif not chat_done and step == ITEMS_STEP and _players_root and not at_post(ID_GINETTE, "chat"):
		for p in _players_root.get_children():
			if p is Player and not (p as Player).is_ai and to_local((p as Player).global_position).distance_to(CHAT_SPOT) < float(NEAR.chat):
				chat_left = CHAT_TIME
				chat_done = true
				_log("Mme Hubert : « Ah, mais c'est vous ! Je vous raconte pour ma hanche… »")
				bark("m06_hubert", 60.0)
				_mark()
				break
	_tick_customers(delta)
	if clock_min >= deadline.fail and step != "done":
		_fail("late", "Midi approche et le cabas est encore à moitié vide : le magasin ferme pour la pause.")
		return
	_sync_t += delta
	if _sync_t >= SYNC_PERIOD:
		_sync_t = 0.0
		_push_state()


func _teleport_to_entrance() -> void:
	var k := 0
	for p in _players_root.get_children():
		if p is Player:
			var spot_l := Vector2(-2.0 + float(k) * 1.1, 12.5)
			if (p as Player).peer_id == ID_KEVIN:
				spot_l = Vector2(6.0, 13.0)
			var w := to_world(spot_l)
			(p as Player).global_position = Vector3(w.x, w.y + 0.6, w.z)
			(p as Player).velocity = Vector3.ZERO
			k += 1


func on_player_left(peer: int) -> void:
	if not is_server():
		return
	if not reading.is_empty() and int(reading.peer) == peer:
		reading = {}
	_mark()


func _log(text: String) -> void:
	messages.append(text)
	if messages.size() > 6:
		messages.pop_front()


func _mark() -> void:
	_dirty = true
	changed.emit()


# --- Réplication ----------------------------------------------------------------------------------------------------------------------------------

func state() -> Dictionary:
	return {"step": step, "started": started, "elapsed": elapsed, "items": items_got, "reading": reading, "chat": chat_left, "chatd": chat_done,
		"coins": coins, "mt": mini_t, "mf": mini_fails, "cust": customers, "cs": cust_seq, "inc": incidents, "pol": politeness, "bt": blocked_total,
		"pen": penalty, "sa": stepaside_left, "pl": pass_left, "result": result, "medal": medal, "clock": clock_min, "messages": messages}


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
	items_got = s.items
	reading = s.reading
	chat_left = s.chat
	chat_done = s.chatd
	coins = s.coins
	mini_t = s.mt
	mini_fails = s.mf
	customers = s.cust
	cust_seq = s.cs
	incidents = s.inc
	politeness = s.pol
	blocked_total = s.bt
	penalty = s.pen
	stepaside_left = s.sa
	pass_left = s.pl
	result = s.result
	medal = s.medal
	clock_min = s.clock
	messages = s.messages
	changed.emit()


# --- Sons et rendu ---------------------------------------------------------------------------------------------------------------------------------

func _audio_events() -> void:
	var now := {"items": items_got.size(), "inc": incidents, "pol": politeness, "coins": coins, "mf": mini_fails, "step": step, "cust": cust_seq}
	if _snd.is_empty():
		_snd = now
		return
	if now.items > _snd.items:
		Sfx.play("beep")
	if now.inc > _snd.inc:
		Sfx.play("sigh")
	if now.pol > _snd.pol:
		Sfx.play("chime")
	if now.coins > _snd.coins:
		Sfx.play("coin")
	if now.mf > _snd.mf:
		Sfx.play("thud")
	if now.step != _snd.step:
		if now.step == "exit":
			Sfx.play("beep")
		elif now.step == "done":
			Sfx.play("fanfare" if result == "win" else "chime")
		elif now.step == "failed":
			Sfx.play("fail")
	_snd = now


func _process(delta: float) -> void:
	_clock += delta
	_audio_events()
	if not is_server():
		for c in customers:
			c.x += float(c.vx) * delta
			c.z += float(c.vz) * delta
		if step == "pay":
			mini_t += delta
		if not reading.is_empty():
			reading.t = float(reading.t) + delta
		chat_left = maxf(chat_left - delta, 0.0)
		stepaside_left = maxf(stepaside_left - delta, 0.0)
		if started and step not in ["done", "failed"]:
			clock_min += delta / secs_per_min
	# Plafond de vitesse « 2 à l'heure » sur tous les acheteurs (humains et compagnons), prédiction client comprise.
	if _players_root:
		for p in _players_root.get_children():
			if p is Player:
				(p as Player).speed_cap = cap_for((p as Player).peer_id) if zone_ok else INF
				if (p as Player).is_ai:
					(p as Player).carrying = false
	_update_customers()


func _update_customers() -> void:
	if not zone_ok:
		return
	var live := {}
	for c in customers:
		live[int(c.id)] = true
		var n: Node3D = _cust_nodes.get(int(c.id))
		if n == null:
			var look := int(c.id) * 7 + 3
			var shirt: Color = [Color(0.3, 0.45, 0.8), Color(0.8, 0.35, 0.3), Color(0.35, 0.65, 0.4), Color(0.85, 0.7, 0.25), Color(0.55, 0.4, 0.7)][look % 5]
			n = CharacterModel.make(shirt, Color(0.22, 0.24, 0.32), Color(0.2, 0.2, 0.25), Player.default_style(look))
			n.name = "Client_%d" % int(c.id)
			get_parent().add_child(n)
			_cust_nodes[int(c.id)] = n
		var w := to_world(Vector2(c.x, c.z))
		n.global_position = w
		var spd := Vector2(float(c.vx), float(c.vz))
		if spd.length() > 0.1:
			var wd := Basis(Vector3.UP, facing) * Vector3(spd.x, 0, spd.y)
			n.rotation.y = atan2(-wd.x, -wd.z)
		(n as CharacterModel).pose_override = {"speed": spd.length()}
	for id in _cust_nodes.keys():
		if not live.has(id):
			(_cust_nodes[id] as Node3D).queue_free()
			_cust_nodes.erase(id)


# --- HUD ------------------------------------------------------------------------------------------------------------------------------------------------------

func objective() -> String:
	match step:
		ITEMS_STEP:
			var missing: PackedStringArray = []
			for it in ITEMS:
				if not (it in items_got):
					missing.append(ITEM_NAMES[it])
			if missing.is_empty():
				return "Le cabas est plein : passez en caisse (à droite, caisse 2)."
			return "Liste de courses : %s." % ", ".join(missing)
		"pay":
			return "Comptez la monnaie : E quand le curseur est dans la zone ▒. Prenez votre temps (la file, un peu moins)."
		"exit":
			return "Sortez du magasin : la porte automatique vous attend."
		"done":
			return "Courses terminées."
		"failed":
			return "Courses ratées."
	return ""


func impatience_bar() -> String:
	var worst := 0.0
	for c in customers:
		worst = maxf(worst, float(c.imp))
	var n := 10
	var f := int(round(clampf(worst, 0.0, 1.0) * n))
	return "[" + "█".repeat(f) + "·".repeat(n - f) + "] %d %%" % int(worst * 100.0)


func coin_bar() -> String:
	var n := 24
	var pos := int(round(mini_pos() * (n - 1)))
	var z0 := int(round(COIN_ZONE.x * (n - 1)))
	var z1 := int(round(COIN_ZONE.y * (n - 1)))
	var s := ""
	for i in n:
		s += "█" if i == pos else ("▒" if i >= z0 and i <= z1 else "·")
	return "[" + s + "]"


func hud_lines() -> PackedStringArray:
	var lines: PackedStringArray = [title, objective()]
	if step in [ITEMS_STEP, "pay", "exit"]:
		lines.append("Il est %s (médaille d'or avant %s)   ·   Vitesse : 2 km/h   ·   Cabas : %d/%d" % [clock_text(clock_min), clock_text(deadline.gold), items_got.size(), ITEMS.size()])
		lines.append("File derrière vous : impatience %s   ·   Incidents : %d/%d   ·   « Après vous » : %d" % [impatience_bar(), incidents, max_incidents, politeness])
	if not reading.is_empty():
		lines.append("Lecture de l'étiquette : %d %%" % int(float(reading.t) / reading_sec * 100.0))
	if chat_left > 0.0:
		lines.append("Mme Hubert vous retient : encore %d s" % int(ceil(chat_left)))
	if step == "pay":
		lines.append("Monnaie %s   Pièces : %d/%d   Ratées : %d" % [coin_bar(), coins, coins_needed, mini_fails])
	if step in ["done", "failed"]:
		lines.append("Temps total de bouchon : %s   ·   Incidents : %d   ·   « Après vous » : %d" % [MissionBase.format_time(blocked_total), incidents, politeness])
	for c in companions():
		lines.append("• %s : %s" % [c.display_name, companion_status(c)])
	for msg in messages.slice(maxi(messages.size() - 3, 0)):
		lines.append("• " + msg)
	return lines


func companion_status(c: Player) -> String:
	var role: String = companion_roles().get(c.peer_id, "")
	match role:
		"caddie":
			var left := 0
			for it in companion_items(c.peer_id):
				if not (it in items_got):
					left += 1
			return "va chercher les palets et le cidre (à 2 à l'heure)" if left > 0 else "a rempli sa part du cabas"
		"bavarde":
			return "papote avec Mme Hubert dans l'allée" if at_post(c.peer_id, "chat") else "va dire bonjour à Mme Hubert"
		"chauffeur":
			return "attend au volant, moteur au ralenti"
	return "attend"


func result_text() -> String:
	if step == "done":
		return "%s — médaille : %s" % ["Courses faites" if result == "win" else "Courses en retard", {"gold": "OR", "silver": "ARGENT", "bronze": "BRONZE"}.get(medal, "aucune")]
	if step == "failed":
		return {"evicted": "Raccompagnée par le gérant", "late": "Pause de midi"}.get(result, "Courses ratées")
	return ""
