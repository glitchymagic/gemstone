class_name Roster
extends RefCounted
## Power Stone 1 roster (SPEC s7). Disc file ids verified in pass 3 by loading each player number in the game's Motion
## Check (0 Falcon ... 9 Valgas, 10 = PA0 Final Valgas) and by the sound-bank order (FOKER RYOUM WANG JACK GANRO
## GARUD AYAME RUJYU KRAKN VAR).
## Only fighters whose models are ripped are playable; the rest say so.

const ALL := [
	{"id": "falcon", "name": "Edward Falcon", "stage": "Londo", "files": "P00/P01", "power": "Red Whirlwind"},
	{"id": "ryoma", "name": "Ryoma", "stage": "Mutsu", "files": "P10/P11", "power": "Master Swordsman"},
	{"id": "wangtang", "name": "Wang-Tang", "stage": "Tong-An", "files": "P20/P21", "power": "Agile Dragon"},
	{"id": "jack", "name": "Jack", "stage": "Manches", "files": "P30/P31", "power": "Mad Clown"},
	{"id": "ayame", "name": "Ayame", "stage": "Oedo", "files": "P60/P61", "power": "Cherry Blossom Dancer"},
	{"id": "gunrock", "name": "Gunrock", "stage": "Dawnvolta", "files": "P40/P41", "power": "Heavy Tank"},
	{"id": "galuda", "name": "Galuda", "stage": "Dullstown", "files": "P50/P51", "power": "Spirit Warrior"},
	{"id": "rouge", "name": "Rouge", "stage": "Mahdad", "files": "P70/P71", "power": "Scorching Beauty"},
	{"id": "kraken", "name": "Kraken", "stage": "Ship", "files": "P80/P81", "power": "-"},
	{"id": "valgas", "name": "Valgas", "stage": "Valgas's Lair", "files": "P90/P91", "power": "Final Valgas"},
	{"id": "finalvalgas", "name": "Final Valgas", "stage": "Final", "files": "PA0", "power": "-", "boss": true},
]

## The game's own select-screen slot table (1ST_READ 0x8C15261A, player numbers left to right): Kraken at the left
## end, Valgas at the right end (both locked until unlocked in the original; open here)
static var SLOTS: Array = DiscTables.list("select_slots")   # from your 1ST_READ.BIN (importer/tables.py)

static func selectable() -> Array:   # the 10 on the character select, in the game's slot order; Final Valgas is boss only
	var out := []
	for n in SLOTS:
		for c in ALL:
			if not c.get("boss", false) and int((c.files as String).substr(1, 1)) == n: out.append(c)
	return out

static func display_name(id: String) -> String:
	for c in ALL:
		if c.id == id: return c.name
	return id.capitalize()

static func is_boss(id: String) -> bool:
	for c in ALL:
		if c.id == id: return c.get("boss", false)
	return false

static func playable(id: String) -> bool:
	return PSModel.available(id)

## The original arcade ladder, logged from the game itself (tools/ladder.py -> assets/ripped/ladder.json).
## The game's own table (1ST_READ 0x8C1525BF): 10 rows of 9 opponents; one of rows 0-7 is served per run (6 regulars,
## mirror match included, then Kraken, Valgas, Final Valgas). Each opponent's stage is the one the logged run showed.
static func load_ladder() -> Array:
	var p := "res://assets/ripped/ladder.json"
	if not FileAccess.file_exists(p): return []
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (j is Dictionary and j.has("rows")): return []
	var picks: Array = j.get("pick_rows", [])
	if picks.is_empty(): return []
	var row: Array = j.rows[int(picks[pick_row(randi() & 0x7FFF) % picks.size()])]
	var st: Dictionary = j.get("stage", {})
	return row.map(func(id): return {"opp": id, "stage": st.get(id, home_stage(id))})

## The game's own pick (1ST_READ 0x0C0A4816, docs/ARCADE-ROW.md): rolled once when the select screen opens,
## row = (u32)(rand() / 32768 * 255) % 8 with the game's C rand() (15-bit); rows 8-9 of the table are never picked,
## row 7 comes up 31 times in 255, the others 32. r = one 15-bit rand() value.
static func pick_row(r: int) -> int:
	return ((r * 255) >> 15) % 8

static func home_stage(id: String) -> String:   # STGn0 = fighter n's home stage (P2 Wang-Tang -> stg20 dojo)
	for c in ALL:
		if c.id == id: return "stg" + (c.files as String).substr(1, 1).to_lower() + "0"
	return "stg00"

static var _faces := {}

## The original portrait + name banner off the disc (FACEnn.BIN, tools/export_faces.py, 4x upscaled): [texture, region]
static func face(id: String) -> Array:
	if _faces.has(id): return _faces[id]
	var res := []
	for c in ALL:
		if c.id != id: continue
		var n := "0123456789A".find((c.files as String).substr(1, 1))
		var path := "res://assets/ripped/ui/face%02d_4x.png" % n
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			# portrait + banner = the left 77 of each 128-px cell (the rest of the texture holds other small art)
			var cell := float(t.get_height())
			var x0 := cell if t.get_width() > t.get_height() else 0.0   # FACE00: FOKKER | FALCON
			res = [t, Rect2(x0, 0, cell * 77.0 / 128.0, cell)]
	_faces[id] = res
	return res
