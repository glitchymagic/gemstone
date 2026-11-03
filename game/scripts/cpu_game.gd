class_name CPUGame
extends RefCounted
## The ORIGINAL's CPU, ported from 1ST_READ.BIN (docs/CPU.md; data = assets/fidelity/cpu_ai.json, tools/cpu_ai.py).
## Same interface as cpu.gd (input: PInput, tick(dt, cam_basis)) so fight.gd can swap it in.
## Per frame it mirrors the AI entry 0x0C04C24C: prev pad = pad, pad = 0; think 0x0C04CFAC (reset triggers, the
## interrupt dispatcher in the original's priority order, the default script); the script interpreter 0x0C04C9C6 runs
## ops until one yields; the pad (logical bits: 0x400 punch, 0x200 kick, 0x4 jump, 0x600 action, D-pad 0x10 up /
## 0x20 down / 0x40 left / 0x80 right, camera-relative) goes into PInput exactly like a human pad.
## Units are the game's: cm, u16 angles (0 = +z, 0x4000 = +x), one tick per 1/60 s frame.
## PORT STATUS: data, dispatcher, selection, interpreter, control flow, registers, waits, presses, jumps, dashes and the
## steering ops follow the decompile. World queries the remaster can't answer yet (stage object lists by the original's
## kinds, the zone code 0x0C09CD32, recoverable reactions 0x0C08E8AC, the chain window +0x7206/+0x7234) go through
## the hooks at the bottom: the arena may provide ai_* methods; without them they report "nothing".

const PUNCH := 0x400
const KICK := 0x200
const JUMP := 0x4
const ACTION := 0x600
static var DIRS: Array = DiscTables.list("cpu_dirs")   # from your 1ST_READ.BIN (importer/tables.py)
const IFS := [29, 30, 31, 32, 33, 59]                              # ops that open a block (0x0C04DFDE)
const NAMES := ["falcon", "ryoma", "wangtang", "jack", "gunrock", "galuda", "ayame", "rouge", "kraken", "valgas"]

static var D := {}
static var LIB := {}          # "set/char" -> situation 0 list (CALL / GOTO)
## The game's C rand 0x0C0DF920 (state 0x0C346A50). The original shares it with everything else; the port keeps one
## state for all CPUs of the match (seed it from the match setup to reproduce a run).
static var rand_state := 1

static func crand() -> int:
	rand_state = (rand_state * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
	return (rand_state >> 16) & 0x7FFF

## (u32)(rand() * (1/32768.0f) * 255.0f) % n: exact in single precision, = (rand * 255) >> 15
static func rnd(n: int) -> int:
	return ((crand() * 255) >> 15) % maxi(n, 1)

static func load_data() -> bool:
	if not D.is_empty(): return true
	var p := "res://assets/fidelity/cpu_ai.json"
	if not FileAccess.file_exists(p): return false
	D = JSON.parse_string(FileAccess.get_file_as_string(p))
	return not D.is_empty()

var me   # a Fighter (untyped: tests/cpu_replay.gd drives the AI with stand-in objects carrying the disc's logged state)
var arena
var input := PInput.new()
var level := 9                 # 0x0C7F305C
var ok := false
var ch := 0                    # character index (Final Valgas and unknown ids -> the fallback)
var fight_index := 0           # REG_FIGHT (op 22): the arcade fight (0 = fight 1: the scripts play it passive)

# ---- the work record (0x0C366F40 + index * 0x254) ----
var phase := 0                 # +0x00 scratch of the running op
var mode := 0                  # +0x04
var intlv := 1                 # +0x06
var mask := 1                  # +0x08
var ip_s := ""                 # +0x0C: script (address key in D.code)
var ip_i := 0                  #        instruction index in it
var timer := 600               # +0x14
var cnt := 0                   # +0x18
var wait_n := 0                # +0x1A
var count := 0                 # +0x1C
var reg := 0                   # +0x26
var dirflag := 0               # +0x2A
var table := 0                 # +0x2C
var last_item = null           # +0x30
var active := 0                # +0x38
var latch_tech := 0            # +0x3A
var latch_thrown := 0          # +0x3C
var latch_zone := 0            # +0x3E
var latch_close := 0           # +0x40
var last_hid := 0              # +0x42
var last_pc := -1              # +0x44
var last_opc := -1             # +0x46
var last_st := -1              # +0x48
var last_mvok := -1            # +0x4A
var heading := 0               # +0x4C
var lastx := 0.0               # +0x50
var lastz := 0.0               # +0x58
var stuck := 0                 # +0x5C
static var _STUCK_DBG := OS.has_environment("PS_STUCK_DEBUG")
var tpos := Vector3.ZERO       # +0x60..+0x68 (cm)
var target = null              # +0x6C (a Fighter or a stage object)
var stack: Array = []          # +0x70 RET depth: [ip_s, ip_i, target, tpos, mask, intlv]
var pad := 0                   # +0x2DC
var prev := 0                  # +0x2E0
var go := false                # 0x0C3673EC
var cam_yaw := 0               # 0x0C7F31E0 (u16)
var mv_ok := 2                 # 0x0C7F3050 MV_OK (the fight runs the CPU only in FIGHT: 2)
var fired := 0                 # (tests) the interrupt bit that fired this frame, 1 = the default script, 0 = none
var seen := Vector3.ZERO       # (tests) my position (cm) as the think step saw it this frame

func _init(p_me, p_arena, p_level := 9) -> void:
	me = p_me; arena = p_arena; level = p_level
	ok = load_data()
	ch = maxi(0, NAMES.find(me.char_id))

# ------------------------------------------------------------------------------------------------ world adapter
func opp(): return me.opponent
static func pos_cm(f) -> Vector3: return (f.global_position as Vector3) * 100.0
## The original's state byte +0x71BA. The fidelity core's own id while it runs movement; the remaster states mapped
## to the original's ids otherwise (FIDELITY: replace by the core's ids as they get ported).
static func gstate(f) -> int:
	if f == null: return 0
	if "ai_st" in f: return int(f.ai_st)   # tests/cpu_replay.gd: the logged +0x71BA
	# BUG-41: the core keeps the original's state id in gst in every state now (reactions 27 / 24, launches, thrower 28,
	# thrown 29, KO 8, carry 35 > 0 ...; Fighter.set_state maps the rest). The S-state mapping below said 15 for a fighter
	# in S.DOWN whose gst was 27 (a launch), so hit-confirmed strings (REG_OPP_ST IF_EQ 27) stopped after the first hit
	if "gst" in f: return int(f.gst)
	match f.state:
		Fighter.S.ATTACK: return 10
		Fighter.S.GRAB: return 37
		Fighter.S.CARRY: return 0
		Fighter.S.HITSTUN: return 27
		Fighter.S.DOWN: return 15
		Fighter.S.GETUP: return 16
		Fighter.S.TRANSFORM: return 23
		Fighter.S.POLE: return 34
		Fighter.S.KO, Fighter.S.WIN: return 21
	return 0
static func pc_flag(f) -> int: return 1 if f != null and f.powered else 0
## The attack's hit id the fighter has armed (+0x100): the game's hit steps of the motion being played.
static func hit_id(f) -> int:
	if f == null: return 0
	if "ai_hid" in f: return int(f.ai_hid)   # tests/cpu_replay.gd: the logged +0x100
	if f.ghits == null or not f.ghits.ok: return 0
	var mo: Array = f._motion()
	if str(mo[0]) == "": return 0
	return int(f.ghits.at(str(mo[0]), int(mo[1])).get("hit", 0))
static func ang_to(from: Vector3, to: Vector3) -> int:
	var a := atan2(to.x - from.x, to.z - from.z)
	return int(round(a / TAU * 65536.0)) & 0xFFFF
static func hdist(a: Vector3, b: Vector3) -> int:
	return int(Vector2(b.x - a.x, b.z - a.z).length())
func dir_bits(a: int) -> int:   # 0x0C050180
	return DIRS[(((a - cam_yaw + 0xD000) & 0xFFFF) >> 13) & 7]
func _hook(name: String, default_val, args: Array = []):
	if arena != null and arena.has_method(name): return arena.callv(name, [me] + args)
	if has_method("_w_" + name): return callv("_w_" + name, args)
	return default_val

# ------------------------------------------------------------------------------------------------ the stage objects
## The original's stage objects, read from RAM in a Londo fight (Flycast u1, 10-27: the lists *0x0C7E4078 ..
## *0x0C7E4088 walked by +0x18, object bytes +2 type, +3 owner, +4 kind, +0x20 x/y/z cm, +0x30C item id, +0x30D
## sub-state), and how the remaster's objects map onto them (docs/CPU.md section 12):
##   type 2 kind 1   the throwables (Londo's patio chairs / tables / bins: stgN0_info "throwable")  -> Prop (REST)
##                   (sub-state 6-12 = flying: interrupt 0x100)                                     -> Prop FLYING
##   type 3 kind 5   the Power Stones (3 per round, list *0x0C7E407C)                                -> Gem
##   type 2 kind 7   item chests (+0x30C = the item inside)  /  type 3 kind 6 = the item on the floor -> none yet
##   type 2 kind 2   lamp posts (the pole swing)                                                     -> arena.poles
##   type 2 kind 8   the fountain column / ball (0x400: an object above me)                          -> none
##   type 2 kind 4, type 4 kind 15: window boxes / breakables up on the buildings                   -> none
## FIND_ITEM (44) = kinds 1/18 = a throwable to pick up; op 62 (named FIND_POLE in cpu_ai.json) = kind 5 = a Power
## Stone; FIND_KIND6 (70) = an item on the floor; FIND_KIND7 (71) = an item chest. The carried kind +0x7236 for a
## lifted stage object is 1 (library 9 -> library 14: throw it when the opponent is in range).
class Spot extends RefCounted:
	var global_position := Vector3.ZERO
	var kind := 0
	func _init(p: Vector3, k: int) -> void: global_position = p; kind = k

func _w_ai_objects(op: int) -> Array:
	var out: Array = []
	if arena == null: return out
	match op:
		44:   # kind 1/18: throwables at rest, nobody carrying them
			for pr in arena.get("props") if arena.get("props") != null else []:
				if pr is Prop and (pr as Prop).state == Prop.REST and (pr as Prop).visible: out.append(pr)
		62:   # kind 5: the Power Stones in play
			for g in arena.get("gems") if arena.get("gems") != null else []:
				if g is Node3D and is_instance_valid(g) and (g as Node3D).is_inside_tree(): out.append(g)
		70, 71: return _w_item_objects(op)   # fx-item2 hook
	return out

## --- fx-item2: the AI's item queries (FIND_KIND6 70 = an item on the floor at rest, +0x30D == 0, nobody's;
## FIND_KIND7 71 = an item chest), from the remaster's Items (game/scripts/items.gd)
func _w_item_objects(op: int) -> Array:
	var out: Array = []
	var its = arena.get("items") if arena != null else null
	if its == null: return out
	if op == 70:
		for it in its.items:
			if is_instance_valid(it) and it.holder == null and it.sub == 0 and it.id < 15: out.append(it)
	else:
		for c in its.chests:
			if is_instance_valid(c): out.append(c)
	return out

## interrupt 0x100 (0x0C04CB96): a live object not mine, kind 1/18 in sub-state 6-12 (a thrown stage object)
func _w_ai_incoming():
	if arena == null or arena.get("props") == null: return null
	for pr in arena.props:
		if pr is Prop and (pr as Prop).state == Prop.FLYING and (pr as Prop).thrower != me: return pr
	return null

## interrupt 0x02 (0x0C04CA52): +0x71C8 is a type-2 object -> situation 3.0 with REG = its kind. +0x71C8 is the object
## in hand OR in reach: the disc's log (cpu_falcon_ryoma_L9, Ready phase) fires 3.0 every 6 frames while both stand
## still near objects, and on the first fight frame both press punch there (3.0: kind 2 = a lamp post / pole: action
## within 300 cm; other kinds: opponent past 500 cm -> action = lift it, else punch); lon_3: a fighter at rest with
## +0x71C8 on a patio table (sub-state 0). Remaster: the carried Prop, else a throwable at rest or a pole the core can act on (below).
var _pole_spots: Array = []
## BUG-41: the "in reach" half is used only when the fighter core reports the object its punch would act on
## (`reach_obj`): on the disc that punch starts the object move (a pole: the swing k1/150 > 151 > 152; a stage object:
## k1/153 > 154, travel ~8 cm/frame), which ends the contact. The remaster's punch there is a plain punch, the contact
## stays and 3.0 fires again every few frames: 30/0 took 33-48 % of the port's time and 229 whiffed attack starts at the
## spawn points (386 cm) in 4.5 min (Londo, Falcon vs Ryoma L9). Until the core does the move: the carried object only.
## Otherwise (the default) "in reach" = what the core itself can act on, so the action the 3.0 script presses lands:
## the core's pick-up / object-punch reach (Fighter._reach_prop = arena.nearest_prop 1.45 m: the disc lifted chair 32
## from 144 cm, lon_0), with the core's own filters (3D distance, a prop up on a ledge outside the area is not reachable).
## Poles count only when TOUCHING (OBJ.md 1: +0x71C8 = the object touching me; the pole's collision pushes a body back out
## to 42-62 cm from its axis, k2/211 rows, p50 45): the core catches a pole only from the air, so a pole 0.6-1.1 m away
## held the AI in 3.0 (situation 3.0, REG 2: opponent within 300 cm -> WAIT_GROUND, PRESS action, END) on the ground for
## good: fx-cpu4 b0 (master 2f8da7d, Londo): Wang-Tang idle 90 cm from the lamp post at (-428, -256), 3.0 every 3 frames,
## 290 action presses / min, 30/0 25 % of the fight (disc 30/0 4-19 %, action presses 17-150 / min). PROP_REACH_M /
## POLE_REACH_M were 1.4 / 1.1 m until fx-cpu4.
const REACH_FROM_CORE := false
const PROP_REACH_M := 1.45
const POLE_TOUCH_M := 0.62
func _w_ai_item_held():
	if me.carry != null and is_instance_valid(me.carry): return me.carry
	if REACH_FROM_CORE:
		if "reach_obj" in me and me.reach_obj != null and is_instance_valid(me.reach_obj): return me.reach_obj
		return null
	if arena == null: return null
	var p: Vector3 = me.global_position
	var best = null; var bd := POLE_TOUCH_M
	if arena.has_method("nearest_prop"): best = arena.nearest_prop(p, PROP_REACH_M)
	if best == null and arena.get("props") != null and not arena.has_method("nearest_prop"):
		bd = PROP_REACH_M
		for pr in arena.props:
			if not (pr is Prop) or (pr as Prop).state != Prop.REST or not (pr as Prop).visible: continue
			var d: Vector3 = (pr as Prop).global_position - p
			if d.length() < bd: bd = d.length(); best = pr
		bd = minf(bd, POLE_TOUCH_M)
	if best != null: bd = minf(bd, Vector2(best.global_position.x - p.x, best.global_position.z - p.z).length())
	if arena.get("poles") != null:
		if _pole_spots.size() != arena.poles.size():
			_pole_spots = []
			for q in arena.poles: _pole_spots.append(Spot.new(q, 2))
		for sp in _pole_spots:
			var dh := Vector2(sp.global_position.x - p.x, sp.global_position.z - p.z).length()
			if dh < bd: bd = dh; best = sp
	return best

## The zone code 0x0C09CD32 (interrupt 0x1000 -> situation 8; the wall kick reads the same code, OBJ.md 2): first the
## contact list +0x294 (count +0x2A8): a type-2 object at rest (+0x30D == 0, contact class +0x2A9 == 2, +0x2D9 != 2),
## then the near list +0x2C0 (count +0x2D8, kinds +0x2B8) = the stage's own collision pieces I touch (the list 0x400 (a)
## reads); 0x0C025F7A / 0x0C026076 classify the touch, the first class > 3 is returned: 4-7 = the side I touch, the axis
## heading INTO it = (class - 4) * 0x4000 (the wall kick's init 0x0C0A0984 faces it; the kick-off turns 0x8000 and
## leaves the wall: 10 / 10 logged), so 4 = +z, 5 = +x, 6 = -z, 7 = -x. The dispatcher (0x0C04CC5C) keeps 4 only with
## the opponent at z <= mine, 6 at z >= mine, 5 at x <= mine, 7 at x >= mine: backed against a wall / object with the
## opponent on the open side (disc, 16 logs: 201 of the 230 8.0 selections within 35 cm of the area edge have the
## opponent on the open side of that edge; the selections come from running 140, attacks 87, reactions 71 ...).
## Remaster: a throwable at rest in the core's reach (arena.nearest_prop 1.45 m, the disc's 143 cm lift), else the
## core's own wall contact this frame (Fighter._hit_wall / _wall_normal: pushed by the area's edge or held at a ledge).
## Until fx-cpu4 the port took only props (1.5 m) and read the side the other way round (4 = an object at -z), so it
## fired when the object stood between the fighters, and never at walls: Mode 0x80 share 0.02-0.10 (disc 0.10-0.23).
const ZONE_M := 1.45
var zone_obj = null
func _w_ai_zone() -> int:
	zone_obj = null
	var into := Vector3.ZERO
	if arena != null and arena.has_method("nearest_prop"):
		var o = arena.nearest_prop(me.global_position, ZONE_M)
		if o != null: zone_obj = o; into = (o as Node3D).global_position - me.global_position
	if zone_obj == null and me.has_method("_hit_wall") and bool(me._hit_wall()):
		into = -(me._wall_normal() as Vector3)
	into.y = 0.0
	if into.length() < 0.001: return 0
	if absf(into.z) >= absf(into.x): return 4 if into.z > 0.0 else 6
	return 5 if into.x > 0.0 else 7

## Interrupt 0x400 (a): an object in the near list +0x2C0 (count +0x2D8; the stage's own collision pieces the fighter
## touches, the list the zone code 0x0C09CD32 reads for walls) whose top 0x0C02629E is 60-440 cm above the feet ->
## situation 10.0 (JUMP 6: up onto it). Remaster, with the fighter core: a piece is touched when the core's own move was
## held by a wall this frame (Fighter._hit_wall, the contact the core's wall kick uses: the disc's wall kick reads the
## same near list); its top = the measured floor (Arena.floor_levels) CONTACT_M beyond the contact, into the wall: a floor
## 60-440 cm up and none walkable there. Without the core's contact (tests/cpu_world_replay.gd stand-ins): CONTACT_M
## ahead along the facing (fx-cpu3's test). fx-cpu4: the facing test fired with nothing touched, 60 cm before Londo's
## 240 cm floor face while running at it and in the air beside it: 10.0 jumps that landed on the same floor 44 % (disc
## 20 %) and wall kicks off the face after 27 % of the ground jumps (disc 5 %) [b1, fx-cpu4 ba704fe].
const CONTACT_M := 0.6
const OVERHEAD_NEEDS_CONTACT := true
func _w_ai_object_overhead() -> bool:
	if arena == null or not arena.has_method("floor_levels"): return false
	var into: Vector3 = Vector3(me.facing.x, 0, me.facing.z).normalized()
	if OVERHEAD_NEEDS_CONTACT and me.has_method("_hit_wall"):
		if not bool(me._hit_wall()): return false
		into = -(me._wall_normal() as Vector3); into.y = 0.0
		if into.length() < 0.001: return false
		into = into.normalized()
	var q: Vector3 = me.global_position + into * CONTACT_M
	var ls: Array = arena.floor_levels(q.x, q.z)
	if ls.is_empty(): return false
	var y: float = me.global_position.y
	var up := false
	for l in ls:
		if absf(float(l) - y) <= 0.6: return false   # walkable (the core steps up to 60 cm)
		if float(l) >= y + 0.6 and float(l) <= y + 4.4: up = true
	return up

func _w_ai_kind(obj) -> int:
	if obj is Spot: return (obj as Spot).kind
	if obj is Prop: return 1
	if obj is Gem: return 5
	return 0

func _w_ai_stage() -> String:
	return str(arena.get("stage")) if arena != null and arena.get("stage") != null else "stg00"

## The chain window +0x7206 > +0x7234 (op 82, 0x0C050F80: u8 +0x7206 > s8 +0x7234): the string handler takes the
## next press once the running attack's last attack step is over (the fidelity core: gmo_f >= atk_open), or at once
## when no core attack runs (FIDELITY: +0x7234 itself is not decoded; this is the core's own window)
func _w_ai_chain_open() -> bool:
	if not ("core_atk" in me) or not me.core_atk: return gstate(me) != 10
	return int(me.gmo_f) >= int(me.atk_open)

# ------------------------------------------------------------------------------------------------ the frame
func tick(_dt: float, cam_basis: Basis) -> void:
	if not ok or me == null or opp() == null: input.set_state(Vector2.ZERO, {}); return
	cam_yaw = int(round(atan2(cam_basis.z.x, cam_basis.z.z) / TAU * 65536.0)) & 0xFFFF
	if me.cpu_level >= 0: level = me.cpu_level
	prev = pad; pad = 0; fired = 0
	_think()
	_run()
	_emit()
	if NO_PAD_LATENCY and "_last_in" in me: me._last_in = [input.move, input.held.duplicate(), input.pressed.duplicate()]

## The AI's pad reaches the fighter on the frame it is written: the battle update 0x0C092B8C runs the AI (it writes
## +0x2DC) and then that player's fighter code in the same frame. Disc logs (16 CPU-vs-CPU matches): 1,782 of 1,782 CPU
## jump presses from states 0 / 2 / 31 show state 4 / 5 on the press frame, 271 of 271 punch presses from idle state 10,
## none a frame later. Fighter._delay_input holds every pad one frame (the human pad's latency, measured with tapes), so
## the port's CPU acted a frame late everywhere (fx-cpu4: a 10.0 JUMP 6 from a run rose one frame later than the
## disc's, and its re-check after the RET came 23 cm lower at Londo's 240 cm floor: 60 cm under the top = a second
## JUMP press in the air = a wall kick off the face, 241 of 494 ground 10.0 jumps; disc 17 of 354). The CPU hands the
## fighter this frame's pad (FIDELITY request to the lead: a per-controller latency in Fighter._delay_input instead).
const NO_PAD_LATENCY := true

## The ACTION input is not a button of its own on the disc: 0x600 = punch + kick pressed together (0x0C0A22D6), and when
## no action applies the punch takes it. Disc, 16 logs, CPU 0x600 presses on the ground (620): pick-up 256, grab k1/84 92,
## a punch / object punch (k1/16 91, k1/156, k1/74, k1/18, k1/147 ~50), nothing 45; in the air (453): air punch k1/10 218,
## pole catch 71, air action k1/53 58. The fighter core takes "action" first (grab, pick-up) and "punch" after it on the
## ground, so a grounded, empty-handed CPU sends the punch with it; in the air and while carrying the core tests punch
## BEFORE action (an air attack would beat the pole catch, a throw the drop), so there only "action" goes (FIDELITY
## request to the lead: the air / carry order, then this gate can go). Before fx-cpu4 situation 8's GRAB (8.0: the
## opponent within 300 cm, backed against a wall) pressed an action that did nothing in the port.
func _emit() -> void:
	var m := Vector2(float((pad & 0x80) != 0) - float((pad & 0x40) != 0), float((pad & 0x20) != 0) - float((pad & 0x10) != 0))
	var now := {}
	if pad & ACTION == ACTION:
		now["action"] = true
		if gstate(me) in [0, 2, 31, 32] and _carry_kind() == 0: now["punch"] = true; now["kick"] = true
	else:
		now["punch"] = pad & PUNCH != 0
		now["kick"] = pad & KICK != 0
	now["jump"] = pad & JUMP != 0
	input.set_state(m.limit_length(1.0), now)

func _set_key(k: String) -> String:
	if pc_flag(me): return "PC/%d/%s" % [ch, k]
	if pc_flag(opp()): return "oppPC/%d/%s" % [ch, k]
	return "n/%d/%s" % [ch, k]

func _reset() -> void:
	timer = 600; active = 0; mask = 1

## 0x0C04CCE0: push the running context (ip, target, target position, Mask, IntLv)
func _push() -> void:
	stack.push_back([ip_s, ip_i, target, tpos, mask, intlv])

func _fire(bit: int, m: int, sit: int, sub: int) -> void:
	_push(); active = 1; intlv = bit; mode = m; phase = 0; fired = bit
	_select(sit, sub)

## 0x0C04CE3C
func _select(sit: int, sub: int) -> void:
	var subs: Array = D.select.get(_set_key(str(sit)), [])
	if sub >= subs.size(): return
	var th: Array = subs[sub][0]
	var bands: Array = subs[sub][1]
	var b := 0
	while b < th.size() and not (level < int(th[b])): b += 1
	var lst: Array = bands[mini(b, bands.size() - 1)]   # past the last threshold the original reads the first list
	if b >= th.size(): lst = bands[0]
	var idx := int(lst[rnd(lst.size())])
	table = idx
	var scr: Array = D.scripts.get(_set_key(str(sit)), [])
	if idx < scr.size(): ip_s = str(scr[idx]); ip_i = 0

func _think() -> void:
	var o = opp()
	var st := gstate(me); var ost := gstate(o)
	var p := pos_cm(me); var op := pos_cm(o)
	seen = p
	var mvok := mv_ok
	if last_mvok != mvok: last_mvok = mvok; _reset()
	if last_pc != pc_flag(me): last_pc = pc_flag(me); _reset()
	if last_opc != pc_flag(o): last_opc = pc_flag(o); _reset()
	if last_st != st:
		last_st = st
		if st == 27: _reset()
	timer -= 1
	if timer == 0: _reset()
	if hdist(Vector3(lastx, 0, lastz), p) < 5 and st in [2, 31]: stuck += 1
	else: stuck = 0
	_detour_tick(p, st)
	lastx = p.x; lastz = p.z
	var dist := hdist(p, op)
	var dy := int(op.y - p.y + 100.0)   # (u16)(int)(o.y - p.y + 100) < 200
	# 0x1000
	if _can(0x1000):
		if st in [34, 26, 36, 39]: _fire(0x1000, 0x30, 13, 0); return
		var z := int(_hook("ai_zone", 0))
		if z in [2, 3]: z = 0
		elif z == 4 and p.z < op.z: z = 0
		elif z == 6 and op.z < p.z: z = 0
		elif z == 5 and p.x < op.x: z = 0
		elif z == 7 and op.x < p.x: z = 0
		if z == 0: latch_zone = 0
		elif latch_zone == 0: latch_zone = 1; _fire(0x1000, 0x80, 8, 0); return
	# 0x800: recover from a reaction / break a throw, by the level's chance
	if _can(0x800):
		if bool(_hook("ai_can_recover", false)):
			if latch_tech == 0 and rnd(100) < int(D.evade_pct_by_level[clampi(level, 0, 31)]):
				_fire(0x800, 0x10, 11, 0); return
			latch_tech = 1
		else: latch_tech = 0
		if st == 29:
			if latch_thrown == 0 and rnd(100) < int(D.thrown_pct_by_level[clampi(level, 0, 31)]):
				_fire(0x800, 0x10, 11, 0); return
			latch_thrown = 1
		else: latch_thrown = 0
	# 0x400: objects over / near me (stage-object hooks)
	if _can(0x400) and st in [0, 2, 31, 5]:
		if bool(_hook("ai_object_overhead", false)): _fire(0x400, 0x00, 10, 0); return
		var obj = _hook("ai_object_k12", null)
		if obj != null and not (dist <= 300 and dy >= 0 and dy < 200):
			_fire(0x400, 0x01, 10, 1); target = obj; tpos = pos_cm(obj); return
	if _can(0x200):
		if st in [15, 16]: _fire(0x200, 0x90, 12, 0); return
		if st == 13: _fire(0x200, 0x91, 12, 1); return
	if _can(0x100) and _hook("ai_incoming", null) != null: _fire(0x100, 0x90, 9, 0); return
	if _can(0x80) and ost in [36, 34]: _fire(0x80, 0x70, 7, 0); return
	if _STUCK_DBG and stuck > 0 and stuck % 60 == 0:
		print("CPUSTUCK f%d %s stuck %d st %d intlv 0x%x mask 0x%x mode 0x%x active %d ip %s timer %d tgt %s tpos %s p %s" % [Engine.get_physics_frames(), NAMES[ch], stuck, st, intlv, mask, mode, active, str(ip_s), timer, str(target), str(tpos), str(p)])
	if _can(0x40) and stuck > 60 and st in [2, 31]: stuck = 0; _fire(0x40, 0x60, 6, 0); return
	if _can(0x20) and ost == 15: _fire(0x20, 0x40, 14, 0); return
	if _can(0x10):
		var h := hit_id(o)
		if last_hid != h:
			last_hid = h
			if h != 0:
				rnd(100)   # always < 100: taken, but the rand() is consumed
				var resp: Dictionary = D.response_sub_by_hit_id.get(NAMES[ch], {})
				_fire(0x10, 0x50, 5, int(resp.get(str(h), 0))); return
	var close := dist < 300 and dy >= 0 and dy < 200 and ost != 15
	if _can(8) and close and _front(p, op): _fire(8, 0x40, 4, 0); return
	if _can(4):
		if close:
			if latch_close == 0: latch_close = 1; _fire(4, 0x41, 4, 1); return
		else: latch_close = 0
	if _can(2):
		var it = _hook("ai_item_new", null)
		if it != last_item:
			last_item = it
			if it != null: _fire(2, 0x31, 3, 1); reg = int(_hook("ai_kind", 0, [it])); return
		it = _hook("ai_item_held", null)
		if it != null: _fire(2, 0x30, 3, 0); reg = int(_hook("ai_kind", 0, [it])); return
		it = _hook("ai_item_target", null)
		if it != null:
			_fire(2, 0x32, 3, 2); reg = int(_hook("ai_kind", 0, [it])); target = it; tpos = pos_cm(it); return
	if active == 0:
		active = 1; intlv = 1; mask = 0xFFFE; mode = 0x10; timer = 600; stack.clear(); phase = 0; fired = 1
		_select(1, 0)
		if _carry_kind() == 0: mask |= 2
		else: mask &= ~2
		cnt = 0

## +0x7236: the kind (1-16) of the object carried, 0 = none (library script 9 branches on it to throw / use it)
func _carry_kind() -> int:
	if me.carry == null or not is_instance_valid(me.carry): return 0
	return int(_hook("ai_kind", 1, [me.carry]))

func _can(bit: int) -> bool: return (mask & bit) != 0 and intlv < bit

## 0x0C04BFD0 < 0x2000: the opponent within +-45 degrees of my heading
func _front(p: Vector3, op: Vector3) -> bool:
	var h := int(round(atan2(me.facing.x, me.facing.z) / TAU * 65536.0)) & 0xFFFF
	return ((ang_to(p, op) - h + 0x1000) & 0xFFFF) < 0x2000

# ------------------------------------------------------------------------------------------------ the interpreter
func _code() -> Array: return D.code.get(ip_s, [])

func _run() -> void:
	go = true
	var guard := 0
	while go and guard < 256:
		guard += 1
		var c := _code()
		if ip_i >= c.size(): return   # 0xFFFF: the script ran off its end, it stays there
		var ins: Array = c[ip_i]
		_op(int(ins[0]), int(ins[1]) if ins.size() > 1 else 0)

## an op that completes: past itself, scratch cleared, the next op runs this frame
func _done() -> void:
	ip_i += 1; phase = 0; count = 0; go = true

## 0x0C04DFDE: skip to after the matching ELSE / ENDIF
func _skip() -> void:
	var c := _code()
	var d := 1
	var i := ip_i + 1
	while d != 0 and i < c.size():
		var op := int(c[i][0])
		if op == 7: d -= 1
		elif op == 8 and d - 1 == 0: d = 0
		elif op in IFS: d += 1
		i += 1
	ip_i = i - 1   # _done() steps past

func _lib(n: int) -> String:
	var l: Array = D.scripts.get(_set_key("0"), [])
	return str(l[n]) if n < l.size() else ""

func _op(op: int, a: int) -> void:
	var o = opp()
	var p := pos_cm(me)
	match op:
		0:   # END
			active = 0; intlv = 1; mask = 1; phase = 0; go = false
		7: _done()
		8: _skip(); _done()
		9:   # GOTO
			table = a; ip_s = _lib(a); ip_i = 0; phase = 0; go = true
		10:  # CALL
			table = a; stack.push_back([ip_s, ip_i + 1, target, tpos, mask, intlv]); ip_s = _lib(a); ip_i = 0
			phase = 0; go = true
		11:  # RET (depth 0 would spin forever in the original; never happens there)
			if stack.is_empty(): go = false; return
			var s: Array = stack.pop_back()
			ip_s = s[0]; ip_i = s[1]; target = s[2]; tpos = s[3]; mask = s[4]; intlv = s[5]; phase = 0; go = true
		19: reg = hdist(p, pos_cm(o)); _done()
		20: reg = int(pos_cm(o).y - p.y); _done()
		21: reg = int(p.y - pos_cm(o).y); _done()
		22: reg = int(_hook("ai_fight_index", fight_index)); _done()
		25: reg = rnd(a); _done()
		29, 30, 31, 59, 32, 33:   # IF_GT IF_LT IF_EQ IF_NE IF_NZ IF_Z: false -> past the matching ELSE / ENDIF
			var t: bool = [reg > a, reg < a, reg == a, reg != a, reg != 0, reg == 0][[29, 30, 31, 59, 32, 33].find(op)]
			if not t: _skip()
			_done()
		57: reg = gstate(o); _done()
		74: reg = gstate(me); _done()
		58: reg = _carry_kind(); _done()   # +0x7236: the kind carried (a lifted stage object = 1)
		84: reg = 0; _done()               # +0x71C8 -> +0x30C: the item id of a held item (stage objects: 0; no items yet)
		75: timer = a; _done()
		77: cnt = a; _done()
		78: reg = cnt; _done()
		79: cnt = 0; _done()
		63: mask |= a & 0xFFFF; _done()
		64: mask &= ~a & 0xFFFF; _done()
		45: target = o; tpos = pos_cm(o); _done()
		53: tpos = Vector3.ZERO; _done()
		85:
			var pts: Array = D.waypoints.get(str(_hook("ai_stage", "stg00")), [])
			var i := rnd(4)
			if i < pts.size(): tpos = Vector3(float(pts[i][0]), float(pts[i][1]), float(pts[i][2]))
			_done()
		42: _wait_until(gstate(me) == 0)
		46: _wait_until(gstate(me) in [0, 2, 31, 5])
		80: _wait_until(gstate(me) in [0, 2, 31])
		81: _wait_until(not gstate(o) in [27, 24, 15, 16])
		82: _wait_until(bool(_hook("ai_chain_open", gstate(me) != 10)))
		43:  # WAIT_LAND (0x0C05103C): yield while above the target position and falling
			var vy: float = (me.vcm.y if "vcm" in me else me.velocity.y)
			_wait_until(not (p.y > tpos.y and vy < 0.0))
		87: _wait_until(not bool(_hook("ai_reacting", false, [o])))
		60:  # WAIT n
			match phase:
				0: go = false; wait_n = a; phase = 1
				1:
					go = false; wait_n -= 1
					if wait_n == 0: phase = 2
				_: _done()
		2: _press(a)
		83: _press_dir(a)
		3: _jump(a, _ang_pos())
		51: _walk(a)
		67: _dash(a)
		1: _keep_dist(a)
		4: _run_to(a, true)
		55: _run_to(a, false)
		56: _sidestep(a)
		76: _move_until_y(a)
		72:  # TARGET_RANDOM (0x0C04FB04)
			tpos.x = float(-500 + 10 * rnd(100)); tpos.y = 0.0; tpos.z = float(-500 + 10 * rnd(100)); _done()
		73:  # TARGET_STAGE (0x0C04FC9E)
			var side := p.x > -p.z - 100.0
			if p.y < 400.0: tpos = Vector3(p.x, 0, 300) if side else Vector3(-550, 0, p.z)
			else: tpos = Vector3(p.x, 0, -100) if side else Vector3(50, 0, p.z)
			_done()
		86: _grab()
		12, 13, 14, 15, 16:   # unused in the scripts; REG reads
			reg = int([0, pc_flag(o), int(me.hp), int(me.gems), hdist(p, tpos)][op - 12]); _done()
		_:   # FIND_* (44 62 70 71: the stage-object adapter above); MOVE50 50 (1 use, 0x0C0517A8, not decoded): done
			if op in [44, 62, 70, 71]: _find(op)
			_done()

## FIND_ITEM 44 (kinds 1/18, list *0x0C7E4078, filter 0x0C0AC55C), FIND_POLE 62 (kind 5, *0x0C7E407C, height
## window), FIND_KIND6 70 (*0x0C7E407C, +0x30D == 0), FIND_KIND7 71 (*0x0C7E4078): every candidate scored
## 2 * dist(me) - dist(opponent), the lowest wins (sorted); none -> target unchanged. REG = found.
## The candidates come from arena.ai_objects(fighter, op) (the original's kinds; not mapped in the remaster yet).
func _find(op: int) -> void:
	var cands: Array = _hook("ai_objects", [], [op])
	var best = null; var bs := INF
	var p := pos_cm(me); var q := pos_cm(opp())
	for c in cands:
		var cp := pos_cm(c)
		var sc := 2.0 * Vector2(cp.x - p.x, cp.z - p.z).length() - Vector2(cp.x - q.x, cp.z - q.z).length()
		if sc < bs: bs = sc; best = c
	if best != null: target = best
	if target != null and is_instance_valid(target): tpos = pos_cm(target)
	reg = 1 if best != null else 0

func _wait_until(cond: bool) -> void:
	if cond: _done()
	else: go = false

## 0x0C050068: the angle to the target position; 0x0C04FED8: the aimed angle (target object, 10-frame lead past 300 cm)
func _ang_pos() -> int:
	if detour_on: return ang_to(pos_cm(me), detour)
	return ang_to(pos_cm(me), tpos)

## Remaster-only (not on the disc): the ported AI steers straight at its goal, and a runner pinned against a wall that
## long gets a waypoint round it (Arena.ai_detour over the measured area), re-planned every DETOUR_EVERY frames until
## the straight line is clear, the goal or waypoint is reached, or DETOUR_LEN frames pass. The stuck count is the disc's
## own (+0x5C, moved < 5 cm while running / walking): its stuck event 0x40 fires at 61 and resets it (the disc gets stuck
## too, docs/CPU.md 0x40), so the detour only follows a stuck run the disc's own escape did not end.
## The disc's escape is short and its count starts again from 0 after it (0x40 fires at 61, the script ends, 61 again ..:
## w9 ladders, Galuda pinned at (1.43, 0.55, 2.59) on stg50 for minutes), so a runner that has not left a PIN_R circle
## in PIN_AFTER running frames counts as pinned too.
const DETOUR_AFTER := 90
const PIN_R := 50              # cm
const PIN_AFTER := 150
const DETOUR_EVERY := 10
const DETOUR_LEN := 240
var detour := Vector3.ZERO     # cm
var detour_on := false
var detour_n := 0
var pin_at := Vector3.ZERO
var pin_n := -1
func _detour_tick(p: Vector3, st: int) -> void:
	if pin_n < 0 or hdist(p, pin_at) > PIN_R: pin_at = p; pin_n = 0
	elif st in [2, 31]: pin_n += 1
	if detour_on:
		detour_n += 1
		if not st in [2, 31, 0, 4, 5, 6, 32] or detour_n > DETOUR_LEN or hdist(p, detour) < 30: detour_on = false; return
		if detour_n % DETOUR_EVERY != 0: return
	elif stuck < DETOUR_AFTER and pin_n < PIN_AFTER: return
	var w = _hook("ai_detour", null, [tpos * 0.01])
	if w == null: detour_on = false; return
	if not detour_on: detour_n = 0
	detour_on = true; detour = (w as Vector3) * 100.0
	if _STUCK_DBG: print("CPUDETOUR f%d %s stuck %d p %s goal %s way %s" % [Engine.get_physics_frames(), NAMES[ch], stuck, str(p), str(tpos), str(detour)])
func _aim() -> int:
	if target != null and is_instance_valid(target):
		var tp := pos_cm(target)
		if hdist(pos_cm(me), pos_cm(opp())) > 300 and "velocity" in target:
			tp += (target.velocity as Vector3) * (100.0 / 60.0) * 10.0
		tpos = tp
	return _ang_pos()
## steering hysteresis on +0x4C: keep the old heading within 0x1000
func _hyst(a: int) -> int:
	if ((a - heading + 0x1000) & 0xFFFF) < 0x2000: return heading
	heading = a; return a
func _tdist() -> int:   # 0x0C0500CA
	return hdist(pos_cm(me), pos_cm(target)) if target != null and is_instance_valid(target) else hdist(pos_cm(me), tpos)

func _press(b: int) -> void:   # op 2 (0x0C050CE0)
	match phase:
		0:
			go = false
			if prev != 0: return
			pad |= b; phase = 2
		1: go = false; pad |= b; phase = 2
		2: go = true; phase = 3
		_: _done()

func _press_dir(b: int) -> void:   # op 83 (0x0C050DAC)
	var d := dir_bits(_aim())
	match phase:
		0:
			go = false
			if prev != 0: return
			pad |= b; phase = 2
		1: go = false; pad |= b; phase = 2
		2: go = false; pad |= b | d; phase = 3
		3: go = false; phase = 4
		_: _done()

func _jump(n: int, a: int, hyst := false) -> void:   # op 3 (0x0C050B5C)
	if hyst: a = _hyst(a)
	match phase:
		0:
			go = false
			if n == 0: n = 1
			count = absi(n); dirflag = 1 if n > 0 else 0; phase = 1
			_jump_hold(a)
		1: go = false; _jump_hold(a)
		_: go = false; ip_i += 1; phase = 0; count = 0   # done, but yields this frame
func _jump_hold(a: int) -> void:
	pad |= JUMP | (dir_bits(a) if dirflag else dir_bits(a + 0x8000))
	count -= 1
	if count == 0: phase = 2

func _walk(n: int) -> void:   # op 51 (0x0C05047A): hold to / away from the aimed target |n| frames
	var a := _hyst(_aim())
	match phase:
		0:
			go = false
			if n == 0: n = 1
			count = absi(n); dirflag = 1 if n > 0 else 0; phase = 1
			_hold(a)
		1: go = false; _hold(a)
		_: _done()
func _hold(a: int) -> void:
	pad |= dir_bits(a) if dirflag else dir_bits(a + 0x8000)
	count -= 1
	if count == 0: phase += 1

func _dash(n: int) -> void:   # op 67 (0x0C0522B0): empty, tap, empty, hold |n| frames (running: hold at once)
	var a := _hyst(_aim())
	match phase:
		0:
			go = false
			if n == 0: n = 1
			count = absi(n); dirflag = 1 if n > 0 else 0
			if gstate(me) == 31: phase = 3; _hold(a)
			else: phase = 1
		1: go = false; pad |= dir_bits(a) if dirflag else dir_bits(a + 0x8000); phase = 2
		2: go = false; phase = 3
		3: go = false; _hold(a)
		_: _done()

func _keep_dist(d: int) -> void:   # op 1 (0x0C0501DC)
	var a := _hyst(_aim())
	var dist := _tdist()
	if phase >= 2: _done(); return
	go = false; phase = 1
	if d < dist - 20: pad |= dir_bits(a)
	elif dist + 20 < d: pad |= dir_bits(a + 0x8000)
	else: phase = 2

func _run_to(d: int, obj: bool) -> void:   # op 4 (0x0C0507A4, the target object) / op 55 (0x0C051E2C, the position)
	var a := _hyst(_aim() if obj else _ang_pos())
	var dist := _tdist() if obj else hdist(pos_cm(me), tpos)
	var tw := dir_bits(a); var aw := dir_bits(a + 0x8000)
	match phase:
		0:
			go = false
			var dash := gstate(me) != 31
			if obj: dash = dash and hdist(pos_cm(me), pos_cm(opp())) <= 300
			if dash: phase = 2   # count 1 -> 0 at once: this frame is empty
			else: phase = 4; _run_hold(d, dist, tw, aw)
		2:   # the dash's tap
			go = false
			if d < dist - 20: pad |= tw
			if dist + 20 < d: pad |= aw
			phase = 3
		3: go = false; phase = 4
		4: go = false; _run_hold(d, dist, tw, aw)
		_: _done()
func _run_hold(d: int, dist: int, tw: int, aw: int) -> void:
	if d < dist - 20: pad |= tw; return
	if dist + 20 < d: pad |= aw; return
	if d < dist - 10: pad |= tw
	if dist + 10 < d: pad |= aw
	phase = 5

func _sidestep(n: int) -> void:   # op 56 (0x0C051AA0): wait, wait, tap, release, hold n frames
	match phase:
		0:
			go = false; dirflag = rnd(2); count = 1
			if gstate(me) == 31: phase = 4
			else: phase = 1
		1:
			go = false; count -= 1
			if count == 0: phase = 2
		2:
			go = false; pad |= _side(); phase = 3
		3: go = false; count = n; phase = 4
		4:
			go = false; var s := _side(); count -= 1
			if count == 0: phase = 5
			pad |= s
		_: _done()
func _side() -> int:
	var a := _aim()
	return dir_bits(a + 0x4000) if dirflag else dir_bits(a - 0x4000)

func _move_until_y(h: int) -> void:   # op 76 (0x0C050322)
	var a := _hyst(_ang_pos())
	var dist := _tdist()
	match phase:
		0: go = false; phase = 1
		1:
			go = false
			if dist - 10 > 0: pad |= dir_bits(a)
			if dist + 10 < 0: pad |= dir_bits(a + 0x8000)
			if float(h) <= pos_cm(me).y: phase = 2
		_: _done()

func _grab() -> void:   # op 86 (0x0C050A56): direction 2 frames, then action
	# the original steers against the contact vector +0x270 (0x0C050A12) = toward the touched object; no object: aim
	var d := dir_bits(ang_to(pos_cm(me), pos_cm(zone_obj)) if zone_obj != null and is_instance_valid(zone_obj) else _aim())
	match phase:
		0: go = false; count = 2; phase = 1
		1:
			go = false; pad |= d; count -= 1
			if count == 0: pad |= ACTION; phase = 2
		2: go = false; pad |= ACTION; phase = 3
		_: _done()
