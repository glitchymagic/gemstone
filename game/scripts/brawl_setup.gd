class_name BrawlSetup
extends Node3D
## Battle Royale setup: up to four fighters, each Human (keyboard 1 / keyboard 2 / a pad) or CPU or off; free-for-all
## or 2 vs 2; any stage. Up/down/left/right move between fields, Cross/A/Enter changes a field forwards,
## Square/X/Backspace backwards, Start/START begins, Circle/B/Esc goes back.

const CTRL := ["CPU", "KEYBOARD 1", "KEYBOARD 2", "PAD 1", "PAD 2", "PAD 3", "PAD 4", "OFF"]
var slots := []          # [{"char": idx into Roster.selectable(), "ctrl": idx into CTRL}]
var team_mode := false
var stage_i := 0
var stages := []
var look_i := 0
var cam: Camera3D
var ui: CanvasLayer
var rows: VBoxContainer
var buttons := {}
var music: AudioStreamPlayer
var t := 0.0
var hint: Label

func _ready() -> void:
	Look.build_environment(self)
	var a := Arena.new(); add_child(a); a.build(9)
	cam = Camera3D.new(); cam.fov = 50; cam.current = true; add_child(cam)
	for c in Roster.ALL:
		var st := "stg" + (c.files as String).substr(1, 1).to_lower() + "0"
		if ResourceLoader.exists("res://assets/ripped/%s_world.glb" % st) or st == "stg00":
			stages.append([st, c.stage])
	var sel := Roster.selectable()
	var picks := ["falcon", "ryoma", "ayame", "wangtang"]
	var pads := Input.get_connected_joypads().size()
	for i in 4:
		var ci := 0
		for k in sel.size(): if sel[k].id == picks[i]: ci = k
		var ctrl := 0
		if i == 0: ctrl = 1
		elif i == 1: ctrl = 4 if pads >= 2 else 0
		slots.append({"char": ci, "ctrl": ctrl})
	ui = CanvasLayer.new(); add_child(ui)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 14)
	ui.add_child(v)
	v.add_child(UI.label("BATTLE ROYALE", 96, Color(1.0, 0.82, 0.2)))
	v.add_child(UI.label("up to four fighters, any mix of players and CPUs", 30, Color(0.9, 0.95, 1.0)))
	rows = VBoxContainer.new(); rows.add_theme_constant_override("separation", 10)
	rows.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rows)
	for i in 4:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 14)
		rows.add_child(h)
		_btn(h, "char%d" % i, 520)
		_btn(h, "ctrl%d" % i, 360)
	var h2 := HBoxContainer.new(); h2.add_theme_constant_override("separation", 14); rows.add_child(h2)
	_btn(h2, "mode", 440); _btn(h2, "stage", 440)
	var h3 := HBoxContainer.new(); h3.add_theme_constant_override("separation", 14); rows.add_child(h3)
	if ResourceLoader.exists("res://scripts/remix.gd"): _btn(h3, "look", 440)
	_btn(h3, "start", 440)
	hint = UI.label("Cross / Enter: change   Square / Backspace: back a step   Start: fight   Circle / Esc: title", 26, Color(0.8, 0.85, 0.9))
	v.add_child(hint)
	music = AudioStreamPlayer.new(); add_child(music)
	var s := Audio.music("S_SELE")
	if s: music.stream = s; music.play()
	_refresh()
	(buttons["char0"] as Button).call_deferred("grab_focus")

func _btn(parent: Control, key: String, w: float) -> void:
	var b := UI.button(key, func(): _change(key, 1))
	b.custom_minimum_size = Vector2(w, 60)
	b.add_theme_font_size_override("font_size", 30)
	parent.add_child(b)
	buttons[key] = b

func _active() -> Array:
	var out := []
	for i in 4: if CTRL[slots[i].ctrl] != "OFF": out.append(i)
	return out

func _change(key: String, d: int) -> void:
	var sel := Roster.selectable()
	if key.begins_with("char"):
		var i := int(key.substr(4))
		var k: int = slots[i].char
		for step in sel.size():   # skip fighters that aren't ripped (none today)
			k = posmod(k + d, sel.size())
			if Roster.playable(sel[k].id): break
		slots[i].char = k
	elif key.begins_with("ctrl"):
		var i := int(key.substr(4))
		var c: int = slots[i].ctrl
		while true:
			c = posmod(c + d, CTRL.size())
			if CTRL[c] == "OFF" and i < 2: continue   # P1 and P2 always play
			break
		slots[i].ctrl = c
	elif key == "mode": team_mode = not team_mode
	elif key == "stage": stage_i = posmod(stage_i + d, stages.size() + 1)
	elif key == "look": look_i = posmod(look_i + d, 4)
	elif key == "start": _start(); return
	_refresh()

func _refresh() -> void:
	var sel := Roster.selectable()
	for i in 4:
		var on: bool = CTRL[slots[i].ctrl] != "OFF"
		(buttons["char%d" % i] as Button).text = "P%d  %s" % [i + 1, sel[slots[i].char].name if on else "-"]
		(buttons["ctrl%d" % i] as Button).text = CTRL[slots[i].ctrl] if CTRL[slots[i].ctrl] in ["CPU", "OFF"] else "PLAYER: " + CTRL[slots[i].ctrl]
	var n := _active().size()
	if team_mode and n != 4: team_mode = false
	(buttons["mode"] as Button).text = "2 VS 2 (P1+P2 vs P3+P4)" if team_mode else "FREE-FOR-ALL"
	(buttons["stage"] as Button).text = "STAGE: " + ("P1'S HOME" if stage_i == 0 else String(stages[stage_i - 1][1]).to_upper())
	if buttons.has("look"): (buttons["look"] as Button).text = "LIGHTING: " + ["ORIGINAL", "NIGHT", "SUNSET", "STORM"][look_i]

func _start() -> void:
	var sel := Roster.selectable()
	var chars := []; var cpu := []; var teams := []; var pads := []; var kbs := []
	for i in _active():
		chars.append(sel[slots[i].char].id)
		var c: String = CTRL[slots[i].ctrl]
		cpu.append(c == "CPU")
		teams.append((0 if i < 2 else 1) if team_mode else chars.size() - 1)
		kbs.append(0 if c == "KEYBOARD 1" else (1 if c == "KEYBOARD 2" else -1))
		pads.append(int(c.substr(4)) - 1 if c.begins_with("PAD") else -1)
	var g := UI.game()
	g.set("lighting", ["original", "night", "sunset", "storm"][look_i])
	g.call("start_brawl", chars, cpu, teams, pads, kbs, "" if stage_i == 0 else String(stages[stage_i - 1][0]))

func _process(dt: float) -> void:
	t += dt
	cam.position = Vector3(sin(t * 0.08) * 10.0, 6.0, -12.0 + cos(t * 0.08) * 2.0)
	cam.look_at(Vector3(0, 1.0, 1.0), Vector3.UP)

func _unhandled_input(e: InputEvent) -> void:
	var f := get_viewport().gui_get_focus_owner()
	var key := ""
	for k in buttons: if buttons[k] == f: key = k
	if (e is InputEventKey and e.pressed and e.physical_keycode == KEY_BACKSPACE) or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_X):
		if key != "" and key != "start": _change(key, -1)
		get_viewport().set_input_as_handled()
	elif (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START):
		_start()
	elif (e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE) or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B):
		UI.game().call("goto_title")
