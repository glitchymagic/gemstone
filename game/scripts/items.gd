class_name Items
extends Node3D
## The disc's item chests and items in a 1-on-1 (fx-item2, BUG-46; rules docs/ITEMS.md 5-7, measured on the disc's
## object logs dumps/fidelity/o_*.obj.jsonl: items_weapon, items_id*, fxitem_id*). Units: the game's cm and frames
## (one tick per 1/60 s fight frame); nodes in metres (cm * 0.01).
## The drop clock (Arena._drop_tick, fx-item) calls drop_chest(spot): a chest (type 2 kind 7, meshes = the 1ST_READ
## common bank parts 56 / 126 / 57 / 58 / 59, tools/item_mesh.py) at the spot holding item_pick(chest number). Logged per
## chest (rows from the drop row c, chest 2 of items_weapon: c 599): it shakes +5 cm on x at c + 320 / back 322 / +5
## from 324, the item appears at c + 355 at spot y + 9 and pops (vy 20, gravity 2 per frame: +110 in 11 frames, back
## in 11), the chest is gone at c + 366, the item is ready (sub 0, can be picked up) at c + 378. A floor item nobody
## comes within 300 cm of is gone floor_life frames after it is ready (logged 457 for 7 / 9, 277 for 8, 362 for the
## rest), then its spot is free again. Food 15-17 (option byte only, never in a normal fight) is eaten on touch.
## Fighters: Fighter "## Items (fx-item2)" (pick-up state 35, the carry family, uses, drop on a hit).

const UNIT := 0.01
const WOBBLE_F := [320, 322, 324]
const OPEN_F := 355
const CHEST_GONE_F := 366
const READY_F := 23          # after the item appears (rows 354 > 377)
const POP_VY := 20.0
const POP_G := 2.0
const SPAWN_UP := 9.0        # cm over the spot
const NEAR_CM := 300.0       # a fighter within this keeps a floor item (like the gems' 300 cm)
const FLOOR_LIFE := {7: 457, 8: 277, 9: 457}
const FLOOR_LIFE_DEFAULT := 362
## the item pick (0x0C0CC72E): category by the chest number in the round, then rand() % count over its list
static var CAT_SEQ: Array = DiscTables.list("item_cat_seq")   # from your 1ST_READ.BIN (importer/tables.py)
static var CATS: Array = DiscTables.list("item_cats")   # from your 1ST_READ.BIN (importer/tables.py)
static var CATS_KRAKEN: Array = DiscTables.list("item_cats_kraken")   # from your 1ST_READ.BIN (importer/tables.py)
## dropped by a hit (OBJ.md 4 "Dropped", the carried object's rule): from 180 cm over the carrier's feet, vy +10,
## gravity 2, 5 cm/frame along the carrier's facing, then at rest where it lands (a floor item again)
const DROP_UP := 180.0
const DROP_VY := 10.0
const DROP_H := 5.0

var arena: Node = null       # Arena
var chests: Array = []       # ItemChest
var items: Array = []        # Item (on the floor, popping, falling or held)
var chest_n := 0             # chests dropped this round (+0xC, cyclic 0..9)
var cat_override := {}       # tape pokes: category index -> forced list (0x0C33CF00.. in fxitem_id* tapes)
## tests/tape_run.gd only: the disc picks chest 1's item on the frame the fight starts, before the tape harness sets
## its rand state to 1, so that one draw is not reproducible: the harness hands over the logged item (-1 = draw it)
var first_item := -1
static var tape_first_item := -1   # set by tests/tape_run.gd before the fight; used by the first chest once
static var _meta := {}

static func meta() -> Dictionary:
	if _meta.is_empty() and FileAccess.file_exists("res://assets/fidelity/items.json"):
		_meta = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/items.json"))
	return _meta

func round_start() -> void:
	clear()
	chest_n = 0

func clear() -> void:
	for c in chests: if is_instance_valid(c): c.queue_free()
	for it in items:
		if is_instance_valid(it):
			if it.holder and is_instance_valid(it.holder): it.holder.item = null; _sheath(it.holder, true)
			it.queue_free()
	chests.clear(); items.clear()

## a spot is taken while a chest or a floor item stands on it (each sets the manager's +0x310[spot] every frame)
func spot_used(i: int) -> bool:
	for c in chests:
		if is_instance_valid(c) and c.spot == i: return true
	for it in items:
		if is_instance_valid(it) and it.spot == i and it.holder == null: return true
	return false

func item_pick() -> int:
	var cat: int = CAT_SEQ[chest_n % CAT_SEQ.size()]
	var kraken := false
	for f in arena.fighters:
		if f.char_id == "kraken": kraken = true
	var lst: Array = (CATS_KRAKEN if kraken else CATS)[cat]
	if cat_override.has(cat): lst = cat_override[cat]
	return int(lst[CPUGame.crand() % lst.size()])

func drop_chest(spot: int, age := -1) -> void:   # age: t on the row it first shows = 0 (chest 1: the disc made it a frame before its first row)
	if spot < 0 or spot >= arena.drop_spots.size(): return
	var c := ItemChest.new()
	c.spot = spot; c.t = age
	if chest_n == 0 and tape_first_item >= 0: first_item = tape_first_item; tape_first_item = -1
	c.item_id = first_item if chest_n == 0 and first_item >= 0 else item_pick()
	if chest_n == 0: first_item = -1
	chest_n = (chest_n + 1) % CAT_SEQ.size()
	c.home = arena.drop_spots[spot]
	add_child(c)
	c.global_position = c.home
	chests.append(c)

func tick() -> void:
	_tape_pokes()
	_attack_opens()
	for c in chests.duplicate():
		c.t += 1
		var dx := 0.0
		if c.t >= WOBBLE_F[0] and not (c.t >= WOBBLE_F[1] and c.t < WOBBLE_F[2]): dx = 5.0 * UNIT
		c.global_position = c.home + Vector3(dx, 0, 0)
		if c.t == OPEN_F or (c.opened and c.item_out == null): _open(c)
		if c.t >= CHEST_GONE_F or (c.opened and c.t - c.open_t >= CHEST_GONE_F - OPEN_F):
			chests.erase(c); c.queue_free()
	for it in items.duplicate():
		if not is_instance_valid(it): items.erase(it); continue
		it.t += 1
		if it.holder != null:
			it.held_t += 1
			_hold_pose(it)
			if it.holder.has_method("item_held_tick"): it.holder.item_held_tick(it.held_t)
			continue
		if it.expire >= 0:
			it.expire -= 1
			if it.expire < 0: items.erase(it); it.queue_free(); continue
		match it.sub:
			16:   # the pop out of the chest: the appear row at spot y + 9, then +20, +18 .. back on it 21 rows later
				var p: Vector3 = it.global_position
				if it.t >= 1 and it.vy > -POP_VY - 0.5:
					p.y += it.vy * UNIT; it.vy -= POP_G
					if it.vy < 0.0 and p.y <= it.rest_y + 0.0001: p.y = it.rest_y; it.vy = -POP_VY - 1.0
				it.global_position = p
				if it.t >= READY_F: it.sub = 0; it.life = 0
			4:    # dropped by a hit: falls to the floor, then rests where it lands
				var p: Vector3 = it.global_position
				p += it.vh * UNIT; p.y += it.vy * UNIT; it.vy -= POP_G
				var fy := _floor_y(p)
				if it.vy < 0.0 and p.y <= fy:
					p.y = fy; it.sub = 0; it.life = 0; it.spot = -1
				it.global_position = p
			0:    # at rest on the floor
				var near := false
				for f in arena.fighters:
					if f.global_position.distance_to(it.global_position) < NEAR_CM * UNIT: near = true; break
				if not near: it.life += 1
				if it.life >= int(FLOOR_LIFE.get(it.id, FLOOR_LIFE_DEFAULT)):
					items.erase(it); it.queue_free()
					continue
				if it.id >= 15:   # food: eaten on touch (0x0C09CB20): +95 / +47 / +23 health
					for f in arena.fighters:
						if f.global_position.distance_to(it.global_position) < 0.8 and f.hp > 0:
							f.hp = mini(Rules.MAX_HP, f.hp + [95, 47, 23][it.id - 15])
							items.erase(it); it.queue_free()
							break
	for s in get_children():
		if s is ItemShot: (s as ItemShot).step(self)

func _floor_y(p: Vector3) -> float:
	if arena.has_area():
		var fy: float = arena.floor_y_at(p.x, p.z, p.y + 0.3, 0.3)
		if fy > -INF: return fy
	return arena.ground_y(p)

## the chest opens (by itself at OPEN_F, or when hit): the item appears at spot y + 9 and pops
func _open(c: ItemChest) -> void:
	if c.item_out != null: return
	var it := Item.make(c.item_id)
	it.spot = c.spot; it.sub = 16; it.vy = POP_VY; it.t = -1   # 0 on the row it appears
	it.rest_y = c.home.y + SPAWN_UP * UNIT
	add_child(it)
	it.global_position = c.home + Vector3(0, SPAWN_UP * UNIT, 0)
	items.append(it)
	c.item_out = it
	if not c.opened: c.opened = true; c.open_t = c.t

## a hit on the chest (an attack sphere / a flying object touching it) opens it at once
func hit_chest_near(p: Vector3, r := 0.8) -> void:
	for c in chests:
		if is_instance_valid(c) and not c.opened and c.global_position.distance_to(p) < r:
			c.opened = true; c.open_t = c.t
			_open(c)

## a fighter's live attack spheres (the game's hit steps of the motion on display) touching a closed chest open it
## (the disc: a hit opens it early, logged 67 / 75 / 223 / 324 frames after the drop; the chest's own body = a 45 cm
## sphere 40 cm over its spot: PROVISIONAL, handler 0x0C05D4E4 not decoded)
const CHEST_BODY := [0.40, 0.45]
func _attack_opens() -> void:
	if chests.is_empty(): return
	for f in arena.fighters:
		if not f.core_atk or f.ghits == null or not f.ghits.ok or not (f.model is PSModel): continue
		var mo: Array = f._motion()
		if not f.ghits.has_move(mo[0]): continue
		var st: Dictionary = f.ghits.at(mo[0], mo[1])
		if int(st.get("hit", 0)) == 0 or int(st.get("aset", 0)) == 0: continue
		var att: Array = f.ghits.world_spheres(f.ghits.atk_sets, int(st.aset), (f.model as PSModel).skeleton(), f)
		for c in chests:
			if is_instance_valid(c) and not c.opened \
					and GameHits.overlap(att, [[c.home + Vector3.UP * CHEST_BODY[0], CHEST_BODY[1]]]):
				c.opened = true; c.open_t = c.t
				_open(c)

## the nearest ready floor item touching the fighter (the pick-up reach of the stage objects, 1.45 m)
func reach_item(f: Node3D, max_d := 1.45) -> Item:
	var best: Item = null; var bd := max_d
	for it in items:
		if not is_instance_valid(it) or it.holder != null or it.sub != 0 or it.id >= 15: continue
		var d := Vector2(it.global_position.x - f.global_position.x, it.global_position.z - f.global_position.z).length()
		if d < bd and absf(it.global_position.y - f.global_position.y) < 1.2: bd = d; best = it
	return best

func take(it: Item, f: Node) -> void:
	it.holder = f; it.sub = 5; it.held_t = 0; it.spot = -1; it.uses = 0
	_hold_pose(it)
	_sheath(f, false)

## Ryoma holding an item: the original does not draw his sword (parts 23 / 24 of P10.MDL, fx-item2-clips' captures)
const HIDE_WHILE_HOLDING := {"ryoma": ["part23", "part24"]}
func _sheath(f: Node, show: bool) -> void:
	if f == null or not (f.get("model") is PSModel): return
	var parts: Array = HIDE_WHILE_HOLDING.get(str(f.get("char_id")), [])
	var inst: Node = (f.model as PSModel).forms.get(false)
	if inst == null: return
	for pn in parts:
		var n := inst.find_child(pn, true, false) as Node3D
		if n: n.visible = show

## let go of a held item: dropped by a hit (falls, rests where it lands) or used up (gone)
func release(it: Item, gone: bool) -> void:
	if not is_instance_valid(it): return
	var f: Node3D = it.holder
	it.holder = null
	_sheath(f, true)
	if gone or f == null:
		items.erase(it); it.queue_free(); return
	it.sub = 4; it.vy = DROP_VY
	var fw: Vector3 = f.get("facing") if f.get("facing") != null else Vector3.FORWARD
	it.vh = Vector3(fw.x, 0, fw.z).normalized() * DROP_H
	it.global_transform = Transform3D(Basis.IDENTITY, f.global_position + Vector3.UP * DROP_UP * UNIT)

## held: in the right hand (joint 8 of every rig = the game's right hand; logged item offset in the hand (3, -10, 15) cm
## for item 1, (-1, -6, 51) for 3, (0, -6, 60) for 5)
const HAND_OFF := {1: Vector3(3, -10, 15), 3: Vector3(-1, -6, 51), 5: Vector3(0, -6, 60)}
func _hold_pose(it: Item) -> void:
	var f: Node3D = it.holder
	if it.id == 9 and f is Fighter:   # carried overhead like a stage object (k2/219 > 220 / 221)
		it.global_transform = Transform3D(f.global_transform.basis.orthonormalized(), f.global_position + (f as Fighter)._local_cm(Fighter.CARRY_AT))
		return
	var pm = f.get("model")
	if pm is PSModel:
		var sk := (pm as PSModel).skeleton()
		if sk:
			var bi := sk.find_bone("b08")
			if bi >= 0:
				var t := sk.global_transform * sk.get_bone_global_pose(bi)
				var b := t.basis.orthonormalized()
				it.global_transform = Transform3D(b, t.origin + b * (HAND_OFF.get(it.id, Vector3.ZERO) as Vector3) * UNIT)
				return
	it.global_transform = Transform3D(f.global_transform.basis.orthonormalized(), f.global_position + Vector3.UP * 1.2)

## tape commands of the fxitem_* / items_id* tapes (they poke the disc's RAM; the remaster reads the same lines):
## 0x0C33CF00..02 = the category-0 list, 0x0C7D85D0 = +0x30C (the item) of the chest in pool slot 39 (the 2nd chest)
func _tape_pokes() -> void:
	var fight := arena.get_parent()
	if fight == null or not ("tape" in fight) or fight.tape_f < 0 or fight.tape_f >= (fight.tape as Array).size(): return
	var row: Array = fight.tape[fight.tape_f]
	if row.size() < 3: return
	for c in row[2]:
		var w := str(c).split(" ", false)
		if w.size() < 3 or w[0] != "poke8": continue
		var a := w[1].hex_to_int(); var v := int(w[2])
		if a >= 0x0C33CF00 and a <= 0x0C33CF02:
			var l: Array = cat_override.get(0, CATS[0].duplicate())
			l[a - 0x0C33CF00] = v; cat_override[0] = l
		elif a == 0x0C7D85D0 and chests.size() > 0:
			var last: ItemChest = chests[chests.size() - 1]
			if last.item_out == null: last.item_id = v

func log_rows() -> Array:   # for tests/tape_run.gd's object log: [kind 7 chest | 6 item, id, x, y, z, sub]
	var out := []
	for c in chests:
		var p: Vector3 = c.global_position / UNIT
		out.append([7, c.item_id, snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), 0])
	for it in items:
		var p: Vector3 = it.global_position / UNIT
		out.append([6, it.id, snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1), it.sub])
	return out

static func _visual(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.scale = Vector3.ONE * UNIT
	Mats.stage_mats(n)
	if HD.look() != "classic": HD.stage_mats(n)
	return n


class ItemChest extends Node3D:
	var spot := -1
	var item_id := 0
	var t := 0
	var home := Vector3.ZERO
	var opened := false
	var open_t := 0
	var item_out: Node3D = null
	func _ready() -> void:
		var m: Dictionary = (Items.meta().get("glb", {}) as Dictionary)
		var v := Items._visual(str(m.get("chest", "res://assets/ripped/items/chest.glb")))
		if v: add_child(v)


class Item extends Node3D:
	var id := 0
	var spot := -1
	var sub := 16                # 16 popping, 0 at rest (ready), 5 held, 14 in use, 4 dropped
	var t := 0
	var vy := 0.0
	var vh := Vector3.ZERO
	var rest_y := 0.0
	var life := 0
	var holder: Node3D = null
	var held_t := 0
	var uses := 0
	var expire := -1             # frames left after a hold-limit drop (logged: gone 51 frames after it)
	static func make(p_id: int) -> Item:
		var it := Item.new()
		it.id = p_id
		var m: Dictionary = (Items.meta().get("glb", {}) as Dictionary)
		var v := Items._visual(str(m.get("item", "res://assets/ripped/items/item%02d.glb")) % p_id)
		if v: it.add_child(v)
		return it


## A use's shot (items 0 / 1 / 2 shoot, 7 / 8 / 10 fly themselves at the opponent, 9 explodes): a point moving in a
## straight line at a fixed speed that hits the first enemy whose body (feet .. +180 cm) comes within `r` cm.
class ItemShot extends Node3D:
	var owner_f: Node3D = null
	var v := Vector3.ZERO        # cm/frame
	var r := 40.0
	var life := 30
	var hits: Array = []         # [[delay frames, record index], ...] after contact (item 10: two hits a frame apart)
	var blast := 0.0             # item 9: the explosion also hits the thrower within this (cm), 6 frames later
	var item_id := 0
	var no_owner := false        # item 9: its explosion is nobody's (40 to both, no gem bonus)
	var force2 := false          # item 10: its 2nd hit lands whatever the 1st did (class 21 is not in the reaction machine)
	var t := 0
	var hit_t := -1
	var hit_from := Vector3.ZERO   # where the hit comes from: 1 m back along the flight (the knockback pushes away from it)
	var victim: Node3D = null
	var visual: Node3D = null
	func step(items: Items) -> void:
		t += 1
		if hit_t >= 0:
			hit_t += 1
			for k in hits.size():
				var h: Array = hits[k]
				if int(h[0]) == hit_t and victim:
					items.apply_hit(null if no_owner else owner_f, victim, int(h[1]), hit_from, null, force2 and k > 0)
			if blast > 0.0 and hit_t == 6 and owner_f and is_instance_valid(owner_f) \
					and owner_f.global_position.distance_to(global_position) < blast * Items.UNIT:
				items.apply_hit(null, owner_f, int(hits[0][1]), hit_from, owner_f)
			if hit_t > 12: queue_free()
			return
		var a := global_position
		if t > 1: global_position += v * Items.UNIT   # the spawn frame shows it where it starts
		if visual: visual.rotation.x += 0.3
		for f in items.arena.fighters:
			if f == owner_f or not Items.hittable(f): continue
			var q: Vector3 = f.global_position
			var dy := global_position.y - q.y
			# swept: the closest the frame's step came to his body axis (a 90 cm/frame shot would jump over it)
			var a2 := Vector2(a.x, a.z); var b2 := Vector2(global_position.x, global_position.z); var q2 := Vector2(q.x, q.z)
			var ab := b2 - a2
			var k := clampf((q2 - a2).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var d := (a2 + ab * k - q2).length()
			if d <= r * Items.UNIT + 0.001 and dy > -0.3 and dy < 2.1:
				victim = f; hit_t = 0
				hit_from = q - Vector3(v.x, 0, v.z).normalized() if Vector2(v.x, v.z).length() > 0.001 else a
				if int(hits[0][0]) == 0: items.apply_hit(null if no_owner else owner_f, f, int(hits[0][1]), hit_from)
				if visual: visual.visible = false
				v = Vector3.ZERO
				return
		items.hit_chest_near(global_position)
		if t >= life: queue_free()


## The item records: 1ST_READ 0x0C33AB08 (20 B; the stage objects' table, OBJ.md 6b) matched to the logged hits by
## class, base and type (b4 = 7: no gem bonus, Rules.game_damage): id 1 -> 4 (class 1 launch, base 30: 31 on Falcon
## with 1 gem), 2 -> 1 (launch, 25 -> 26), 4 -> 8 (tumble, 40 -> 42), 5 -> 22 (tumble 48 -> 50), 7 / 8 -> 32 (tumble 32,
## type 7 -> 32), 9 -> 20 (tumble 40, the bomb hits both: 40 / 40), 10 -> 38 (class 21, 24 + 24), 0 -> 2 then 0 (16, 33).
## Ids 3 / 6 have no exact record (3 logged 52, 6 not logged): 3 uses 8's class with base 50 (PROVISIONAL).
const REC := {0: [2, 0], 1: [4], 2: [1], 3: [8], 4: [8], 5: [22], 6: [8], 7: [32], 8: [32], 9: [20], 10: [38, 38]}
const BASE_OVERRIDE := {3: 50}
static var _recs: Array = []
static func record(i: int) -> PackedByteArray:
	if _recs.is_empty() and FileAccess.file_exists("res://assets/fidelity/items.json"):
		for hx in (meta().get("item_records", []) as Array): _recs.append((str(hx)).hex_decode())
	return _recs[i] if i >= 0 and i < _recs.size() else PackedByteArray()

## the item's hits pass over a fighter landing / lying / getting up from a launch (items_weapon: the 2nd use's shot at
## 1147 with Falcon in k2/99 did nothing, the 3rd hit him the row after he stood up)
static func hittable(f: Node) -> bool:
	if not f.can_be_hit(): return false
	if f.gst in [15, 16]: return false
	return not (f.rx_on and str(f.rx_phase) in ["land", "lie", "splat", "tail"])

func apply_hit(att: Node3D, victim: Node3D, rec_i: int, from: Vector3, self_hit: Node3D = null, force := false) -> void:
	if not is_instance_valid(victim) or victim.hp <= 0: return
	if force and not victim.can_be_hit():   # item 10's 2nd hit on a fighter the stand-in reaction has down: health only
		var r2 := record(rec_i)
		var dmg2 := Rules.game_damage(int(r2[1]), victim.defence(), 1, att.gems if att else 0, false, victim.powered, -1, victim.cpu_level, int(r2[4]))
		victim.hp = Rules.apply_damage(victim.hp, dmg2); victim.rec_ceil = victim.hp
		victim.damaged.emit(victim, dmg2)
		return
	if not Items.hittable(victim): return
	var rec := record(rec_i)
	if rec.size() != 20: return
	var base := int(rec[1])
	var who: Fighter = att as Fighter
	if who and who.item and BASE_OVERRIDE.has(who.item.id): base = int(BASE_OVERRIDE[who.item.id])
	var dmg := Rules.game_damage(base, victim.defence(), 1, who.gems if who else 0, who.powered if who else false,
		victim.powered, who.cpu_level if who else -1, victim.cpu_level, int(rec[4]))
	victim.item_react_rec = rec
	victim.receive_hit(dmg, 9.0, true, from, who if who else (self_hit as Fighter))
	victim.item_react_rec = PackedByteArray()
	victim.rec_ceil = victim.hp   # logged: item damage never comes back (198 held to the end in items_id4)
	if who: who.stats.hits += 1; who.stats.dmg_dealt += dmg


## Per item id, what a use does (measured on the disc's logs; Ryoma P1 vs Falcon P2, Londo, P1 300+ cm from P2):
## use = the floor-use motion (kind, id) and its rows; shot = [spawn frame of the use, cm forward, cm up, cm/frame,
## hit radius cm, life frames]: aimed at the opponent (the logged P1 faced away from P2 and still hit him); "reach" =
## a hit on that use frame when the opponent is within `reach` cm (ids 3 / 4 / 5: k2/197 hit at 281 cm on frame 14,
## PROVISIONAL: the item's own hit object is not decoded); "fly" = the item itself leaves the hand (used up).
## Fits: id 1 hits at 333 cm on frame 23 and 605 on frame 26 (90.7 cm/frame from frame 20, 61 cm out); id 2 at 317 on
## frame 15 and 1099 on frame 35 (39.1 cm/frame from frame 11, 70 out, radius 90.6); ids 7 / 8 / 10 leave on k2/235
## frame 10 from (70, 177) at 25 cm/frame at the hip (ITEMS.md 6; hit row 22 at 317 cm); id 9 = the carry throw k1/60
## (28 rows; it explodes on him: 40 to both, the thrower 6 frames later, 317 cm away).
## uses = used up after that many uses (0: 2, 2: 4; thrown: 1); hold = dropped this many frames after the pick-up.
const USE := {
	0: {"use": [2, 243], "n": 52, "shot": [20, 60.0, 160.0, 20.0, 60.0, 40], "uses": 2},
	1: {"use": [2, 245], "n": 31, "shot": [20, 61.0, 100.0, 90.7, 30.0, 8]},
	2: {"use": [2, 86], "n": 39, "shot": [11, 70.0, 157.0, 39.1, 90.6, 30], "uses": 6},
	3: {"use": [2, 197], "n": 45, "reach": [13, 345.0], "hold": 600},
	4: {"use": [2, 197], "n": 45, "reach": [13, 345.0], "hold": 600},
	5: {"use": [2, 197], "n": 45, "reach": [13, 345.0]},
	6: {"use": [2, 253], "n": 45, "reach": [13, 345.0]},
	7: {"use": [2, 235], "n": 36, "shot": [10, 70.0, 177.0, 25.0, 0.0, 40], "fly": true, "uses": 1, "delay": 2},
	8: {"use": [2, 235], "n": 36, "shot": [10, 70.0, 177.0, 25.0, 0.0, 40], "fly": true, "uses": 1, "delay": 2},
	9: {"use": [1, 60], "n": 28, "shot": [15, 50.0, 80.0, 32.0, 50.0, 40], "fly": true, "uses": 1, "blast": 400.0, "no_owner": true},
	10: {"use": [2, 235], "n": 36, "shot": [10, 70.0, 177.0, 25.0, 72.0, 40], "fly": true, "uses": 1, "force2": true},
}
## carry families (item_code.json items.family_by_id): pick-up, idle, walk, jump crouch, air, land, use, air use;
## family 195 runs (202 > 203, stop 204) instead of walking
static func family(id: int) -> Array:
	var fb: Dictionary = ((_code().get("items", {}) as Dictionary).get("family_by_id", {}) as Dictionary)
	return fb.get(str(id), [237, 238, 239, 240, 241, 242, 245, 246])
static var _ic := {}
static func _code() -> Dictionary:
	if _ic.is_empty() and FileAccess.file_exists("res://assets/fidelity/item_code.json"):
		_ic = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/item_code.json"))
	return _ic

## a use's shot from the fighter, aimed at the opponent's body
func shoot(f: Fighter, id: int, opp: Fighter) -> void:
	var u: Dictionary = USE.get(id, {})
	var s: Array = u.get("shot", [])
	if s.is_empty(): return
	var sh := ItemShot.new()
	sh.owner_f = f; sh.item_id = id; sh.r = float(s[4]); sh.life = int(s[5])
	var recs: Array = REC.get(id, [8])
	var d0 := int(u.get("delay", 0))
	sh.hits = [[d0, recs[0]]]
	if recs.size() > 1: sh.hits.append([d0 + (1 if id == 10 else 9), recs[1]])
	sh.no_owner = u.get("no_owner", false); sh.force2 = u.get("force2", false)
	sh.blast = float(u.get("blast", 0.0))
	add_child(sh)
	var fw := f.facing; fw.y = 0; fw = fw.normalized()
	if opp:   # it leaves toward him (the logged P1 faced away from P2 and the shot still went at him)
		var to := opp.global_position - f.global_position; to.y = 0
		if to.length() > 0.01: fw = to.normalized()
	var from := f.global_position + fw * float(s[1]) * UNIT + Vector3.UP * float(s[2]) * UNIT
	var aim := from + fw
	if opp: aim = opp.global_position + Vector3.UP * (1.07 if u.get("fly", false) else (from.y - f.global_position.y))
	var d := aim - from
	if not u.get("fly", false): d.y = 0.0   # the shooters' shots fly level
	sh.v = d.normalized() * float(s[3]) if d.length() > 0.001 else fw * float(s[3])
	sh.global_position = from
	if u.get("fly", false) and f.item:   # the item itself is the shot
		var v := Items._visual(str((meta().get("glb", {}) as Dictionary).get("item", "res://assets/ripped/items/item%02d.glb")) % id)
		if v: sh.add_child(v); sh.visual = v
