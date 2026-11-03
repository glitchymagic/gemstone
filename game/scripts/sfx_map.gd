class_name SfxMap
extends Node
## BUG-36: the original's sound cues (docs/SOUND.md). The disc's sound chip was logged per frame in Flycast while input
## tapes drove each action (tools/sndlog.py); tools/sndcues.py turned every key-on into a cue in
## res://assets/fidelity/sfx_map.json and cut the samples it names off the disc banks into res://assets/audio/se/.
## This node watches each fighter from outside (the motion the model plays + its motion frame, health) and starts the
## same samples on the same frames:
##   motion[fighter][kK_MMM][frame]  a motion reaching that frame (voices, swings, jumps, landings, footsteps)
##   hit[attacker][kK_MMM]           the frame the victim's health drops (impact), by the attacker's motion
## STG0N_nnn = sample nnn of stage stgN0's own bank (STG0N.BIN: landing / steps / falls on its ground), only there.
## PS_SFX_LOG=path writes one line per started sample: tape frame, fighter slot, sample id, trigger.

const MAP := "res://assets/fidelity/sfx_map.json"
const SE := "res://assets/audio/se/%s.wav"
const POOL := 16
const BANK := {"falcon": "FOKER", "ryoma": "RYOUM", "wangtang": "WANG", "jack": "JACK", "gunrock": "GANRO",
	"galuda": "GARUD", "ayame": "AYAME", "rouge": "RUJYU", "kraken": "KRAKN", "valgas": "VAR_1", "finalvalgas": "VAR_2"}

var fight: Node
var data := {}
var stage_bank := "STG00"
var rng := RandomNumberGenerator.new()
var _last := []      # per fighter: [key, frame, hp]
var _pool: Array[AudioStreamPlayer] = []
var _streams := {}
var _log: FileAccess
var _due := []       # [frames left, cue, slot, why]
var _phase := 0
var mute := false

static func make(f: Node, stage: String) -> SfxMap:
	if not FileAccess.file_exists(MAP): return null
	var s := SfxMap.new(); s.name = "SfxMap"; s.fight = f
	s.data = JSON.parse_string(FileAccess.get_file_as_string(MAP))
	if not (s.data is Dictionary): return null
	s.stage_bank = "STG0" + stage.substr(3, 1).to_upper()   # stage stgN0 loads STG0N.BIN (logged: stg10 -> STG01)
	s.rng.seed = 1
	if OS.has_environment("PS_SFX_LOG"): s._log = FileAccess.open(OS.get_environment("PS_SFX_LOG"), FileAccess.WRITE)
	f.add_child(s)

	return s

## The motion a fighter shows this frame as the original's key ("kK_MMM", P-prefixed in the Power Change form) and its
## motion frame (the remaster's tape log uses the same: Fight.tape_row)
static func motion_of(f: Fighter) -> Array:
	if not (f.model is PSModel): return ["", -1]
	var pm := f.model as PSModel
	var key := GameHits.key_of(pm.current_clip())
	if key.length() != 6 or key[0] != "k": return ["", -1]
	# core attacks count the game's own motion frame (gmo_f); clips: the RAM captures start one frame after the game's
	# frame 0 (Fighter._motion), so game frame = clip frame + 1
	var fr: int = f.gmo_f if f.core_atk else int(pm.clip_pos() * 60.0 + 0.001) + 1
	return [("P" if f.powered else "") + key, fr]

## Once per physics frame, before the fighters move (the state the tape log writes for frame TF)
func tick(fighters: Array, tf: int) -> void:
	while _last.size() < fighters.size(): _last.append(["", -1, -1])
	for i in fighters.size():
		var f: Fighter = fighters[i]
		var mo := motion_of(f)
		var l: Array = _last[i]
		if mo[0] != "" and (mo[0] != l[0] or mo[1] != l[1]):
			var md: Dictionary = data.get("motion", {})
			var own: String = "_k2" if str(mo[0]).contains("k2_") else f.char_id   # kind 2 = the shared bank
			var c: Dictionary = (md.get(own, {}) as Dictionary).get(mo[0], {})
			var pool: Dictionary = (md.get("_all", {}) as Dictionary).get(mo[0], {})   # basic moves, every fighter
			if not c.is_empty() or not pool.is_empty():
				# every motion frame reached since the last tick (a new motion / a loop: from its frame 0), so a frame
				# the remaster's clock steps over (or the clip's missing frame 0) still sounds
				var a: int = int(l[1]) + 1 if mo[0] == l[0] and int(mo[1]) > int(l[1]) else 0
				if int(mo[1]) - a > 2: a = int(mo[1])   # a clip entered mid-way (blend / seek): this frame only
				for fr in range(a, int(mo[1]) + 1):
					if c.has(str(fr)): _cue(c[str(fr)], i, tf, "%s@%d" % [mo[0], fr])
					elif pool.has(str(fr)): _cue(pool[str(fr)], i, tf, "all:%s@%d" % [mo[0], fr])
		if l[2] >= 0 and f.hp < l[2]:
			var a: Fighter = f.last_hit_by if f.last_hit_by else f.opponent
			if a:
				var am := motion_of(a)
				# the impact = the attack record's sound byte rec[0x12] (99 = none); a record the logs never landed:
				# the attacker's motion, else the disc's most common impact
				var rec: PackedByteArray = f.rx_rec
				var im: Dictionary = data.get("impact", {})
				var hm: Dictionary = data.get("hit", {})
				if rec.size() == 20 and im.has(str(rec[0x12])): _cue(im[str(rec[0x12])], i, tf, "rec:%d" % rec[0x12])
				elif rec.size() != 20 or rec[0x12] != 99:
					var h = (hm.get(a.char_id, {}) as Dictionary).get(am[0], hm.get("_any", {}))
					if h is Dictionary and h.has("pick"): _cue(h, i, tf, "hit:" + str(am[0]))
			# the victim's voice: by the record's rec[4] (4 = always the same line), else one of his hurt lines, as often
			# as the disc says one, hurt._delay frames after the hit
			var hv: Dictionary = data.get("hurt", {})
			var rr: PackedByteArray = f.rx_rec
			var hc = hv.get(str(rr[4]) if rr.size() == 20 and hv.has(str(rr[4])) else "_any", {})
			if hc is Dictionary and hc.has("pick"):
				var pk := {}
				for k in hc["pick"]: pk["SELF_%03d" % int(k)] = hc["pick"][k]
				_due.append([int(hv.get("_delay", 2)), {"n": hc["n"], "pick": pk}, i, "hurt"])
		if l.size() > 3:
			if f.gems > int(l[3]): _event("gem", i, tf)
			elif f.gems < int(l[3]): _event("gem_drop", i, tf)
		_last[i] = [mo[0], mo[1], f.hp, f.gems]
	var ph := int(Fight.FLOW_PHASE.get(fight.phase, 0)) if fight is Fight else 0   # the original's round phase byte
	if ph == 4 and _phase == 3:   # the KO call (phase 4 also = TIME: then nobody is at 0)
		for i in fighters.size():
			if (fighters[i] as Fighter).hp <= 0: _event("ko", i, tf); _event("ko_voice", i, tf)
	_phase = ph
	for d in _due.duplicate():
		d[0] -= 1
		if d[0] <= 0: _due.erase(d); _cue(d[1], d[2], tf, str(d[3]))

## Samples seen on >= half of the cue's entries all play (layered); the rest are the original's random picks: one of them,
## weighted by how often the disc chose it, as often as the disc played any of them (when that is >= half the entries)
## A stage's own samples (STG0N_) play only on that stage, weighed against the entries logged there (ns).
func _cue(c: Dictionary, slot: int, tf: int, why: String) -> void:
	var n := maxf(1.0, float(c.get("n", 1)))
	var ns: Dictionary = c.get("ns", {})
	var pick: Dictionary = c.get("pick", {})
	var alt := {}   # group ("" or the stage bank) -> [[sample, w], ...]
	for s in pick:
		var g := ""
		if str(s).begins_with("STG0"):
			g = str(s).substr(0, 5)
			if g != stage_bank: continue
		var w := float(pick[s]) / (maxf(1.0, float(ns.get(g, 1))) if g != "" else n)
		if w >= 0.5: _play(str(s), slot, tf, why)
		else:
			if not alt.has(g): alt[g] = []
			alt[g].append([str(s), w])
	for g in alt:
		var tot := 0.0
		for a in alt[g]: tot += float(a[1])
		if tot < 0.5 or rng.randf() >= tot: continue   # as often as the disc played one of them (83% of hits: a voice)
		var r := rng.randf() * tot
		for a in alt[g]:
			r -= float(a[1])
			if r <= 0.0: _play(str(a[0]), slot, tf, why); break

func _play(s: String, slot: int, tf: int, why: String) -> void:
	var info: Dictionary = (data.get("samples", {}) as Dictionary).get(s, {})
	var file := s
	if s.begins_with("SELF_"):   # the fighter's own voice bank, same index for every fighter
		var fs: Array = fight.fighters if fight else []
		var cid: String = (fs[slot] as Fighter).char_id if slot >= 0 and slot < fs.size() else ""
		if cid == "finalvalgas" or not BANK.has(cid): return   # VAR_2's layout was never logged (docs/SOUND.md)
		file = str(BANK[cid]) + s.substr(4)
	if _log: _log.store_line("%d %d %s %s" % [tf, slot, s, why])
	if mute: return
	if not _streams.has(file):
		var p := SE % file
		_streams[file] = load(p) if ResourceLoader.exists(p) else null
	var st: AudioStream = _streams[file]
	if st == null: return
	if _pool.is_empty():
		for k in POOL:
			var ap := AudioStreamPlayer.new(); add_child(ap); _pool.append(ap)
	var pick: AudioStreamPlayer = _pool[0]
	for ap in _pool:
		if not ap.playing: pick = ap; break
	pick.stream = st; pick.volume_db = float(info.get("db", 0.0)); pick.play()

## Events (sfx_map.json event): gem count up / down, the KO call (round phase 3 -> 4) + the KO'd fighter's voice when the
## KO freeze ends (delay frames)
func _event(kind: String, slot: int, tf: int) -> void:
	var c = (data.get("event", {}) as Dictionary).get(kind, {})
	if not (c is Dictionary and c.has("pick")): return
	if int(c.get("delay", 0)) > 0: _due.append([int(c["delay"]), c, slot, kind])
	else: _cue(c, slot, tf, kind)

func _exit_tree() -> void:
	if _log: _log.close()
