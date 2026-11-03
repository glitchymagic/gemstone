extends Node
## fx-flow (lane pstrailer2, docs/FLOW.md): the original's automatic arcade screens between fights, timed in frames as
## logged in Flycast (tools/flowlog.py: o_round, o_screens, o_cont):
##   fight won  -> 1036 frames (world map, stage name, "STAGE N", the VS screen, the loading map) -> the next fight
##   fight lost (two drawn rounds count as lost) -> "CONTINUE?" 10 .. 0, count 10 on frame 2, one count per 91 frames;
##                 START / A continues (character select, then the same opponent); no input: the countdown ends on
##                 frame 1002 -> "THE END" 307 frames -> title
## No results / stats screen in between (the original has none). The original's own screen art (map, VS portraits) is
## not ripped: this shows the disc's HUD portraits and names over the same timings.
var kind := "next"        # next | continue
var f := 0
var over := false
var bg: ColorRect
var big: Label
var small: Label
var faces: Control
const NEXT_LEN := 1036
const BOSS_LEN := 167      # Valgas -> Final Valgas: straight on after his change (no map / VS screens, o_ladder)
const CONT_FIRST := 2
const CONT_EVERY := 91
const CONT_FROM := 10
const CONT_LEN := 1002
const OVER_LEN := 307

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ui := CanvasLayer.new(); add_child(ui)
	bg = ColorRect.new(); bg.color = Color(0.02, 0.03, 0.08); bg.set_anchors_preset(Control.PRESET_FULL_RECT); ui.add_child(bg)
	faces = Control.new(); faces.set_anchors_preset(Control.PRESET_FULL_RECT); faces.draw.connect(_draw_faces); ui.add_child(faces)
	big = UI.label("", 110, Color(1, 0.85, 0.25)); big.set_anchors_preset(Control.PRESET_CENTER); ui.add_child(big)
	small = UI.label("", 40, Color(1, 0.95, 0.8)); small.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); ui.add_child(small)
	_refresh()

func _game() -> Node:
	return UI.game()

func _refresh() -> void:
	var g := _game()
	if g == null: return
	var chars: Array = g.get("chars")
	if kind == "boss":
		big.text = ""; small.text = ""
	elif kind == "next":
		var step: int = int(g.get("arcade_step"))
		var lad: Array = g.get("ladder")
		big.text = "STAGE %d" % (step + 1)
		var opp: String = str(lad[step].opp) if step < lad.size() else ""
		small.text = "%s  VS  %s" % [Roster.display_name(str(chars[0])).to_upper(), Roster.display_name(opp).to_upper()]
	elif not over:
		big.text = "CONTINUE?  %d" % maxi(0, CONT_FROM - (f - CONT_FIRST + 1) / CONT_EVERY) if f >= CONT_FIRST else "CONTINUE?"
		small.text = "PRESS START BUTTON"
	else:
		big.text = "THE END"; small.text = ""
	big.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - big.size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.42)
	small.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - small.size.x * 0.5, get_viewport().get_visible_rect().size.y * 0.72)
	faces.queue_redraw()

func _draw_faces() -> void:
	if kind != "next" or _game() == null: return
	var g := _game()
	var chars: Array = g.get("chars")
	var step: int = int(g.get("arcade_step")); var lad: Array = g.get("ladder")
	var ids := [str(chars[0]), str(lad[step].opp) if step < lad.size() else ""]
	var vs := faces.size
	for i in 2:
		var fc := Roster.face(ids[i])
		if fc.is_empty(): continue
		var h := vs.y * 0.45; var w := h * 77.0 / 128.0
		faces.draw_texture_rect_region(fc[0], Rect2(Vector2(vs.x * (0.18 if i == 0 else 0.82) - w * 0.5, vs.y * 0.08), Vector2(w, h)), fc[1])

func _physics_process(_dt: float) -> void:
	f += 1
	var g := _game()
	if g == null: return
	if kind == "next" or kind == "boss":
		if f >= (BOSS_LEN if kind == "boss" else NEXT_LEN): g.call("next_arcade_fight"); return
	elif not over:
		if f >= CONT_FIRST and _start_pressed(): g.call("continue_arcade"); return
		if f >= CONT_LEN: over = true; f = 0
	elif f >= OVER_LEN:
		g.call("goto_title"); return
	_refresh()

var _was := true   # a button still held from the fight doesn't count: a new press continues
func _start_pressed() -> bool:
	var now := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)
	for p in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(p, JOY_BUTTON_START) or Input.is_joy_button_pressed(p, JOY_BUTTON_A): now = true
	var hit := now and not _was
	_was = now
	return hit
