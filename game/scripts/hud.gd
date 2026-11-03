class_name HUD
extends CanvasLayer
## Original-layout HUD: health bars top-left/top-right with names, three gem slots each,
## power gauge under the bar when changed, timer top centre, round-win marks, announcer text.

var fight   # Fight, or the replay theater (same fighters / cpu_flags / wins / timer fields)
var draw: Control
var msg := ""
var msg_t := 0.0
var msg_total := 1.0
var msg_y := 0.45        # baseline, fraction of the screen height (the winner's name sits low, off his face)

func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	draw = Control.new()
	draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw.draw.connect(_draw_hud)
	add_child(draw)

func announce(text: String, secs: float, y_frac := 0.45) -> void:
	msg = text; msg_t = secs; msg_total = secs; msg_y = y_frac

func _process(dt: float) -> void:
	msg_t = maxf(0.0, msg_t - dt)
	draw.queue_redraw()

func _draw_hud() -> void:
	if fight == null or fight.fighters.size() < 2: return
	if fight.fighters.size() > 2:
		_draw_multi(); return
	var vs := draw.size
	var font := ThemeDB.fallback_font
	# fx-flow (the original's HUD, logged): health bars, gems and the clock only while the round is live (phase 3); the
	# intro and Ready show just the arcade TIME, the KO / TIME call and the poses show TIME + "PLEASE WAIT"
	if fight is Fight:
		var fg := fight as Fight
		if fg.arcade_step >= 0: _draw_elapsed(fg, font)
		if fg.phase != Fight.R.FIGHT and fg.phase != Fight.R.DONE:
			if fg.phase == Fight.R.KO or fg.phase == Fight.R.ROUND_END:
				for i in 2:
					var t := "PLEASE WAIT"
					var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
					var px := 40.0 if i == 0 else vs.x - 40.0 - tw
					draw.draw_string_outline(font, Vector2(px, 64), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color(0, 0, 0))
					draw.draw_string(font, Vector2(px, 64), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1, 0.9, 0.2))
			_draw_msg(vs, font)
			return
	var w := vs.x * 0.36
	var ps := 118.0
	for i in 2:
		var f: Fighter = fight.fighters[i]
		var fc := Roster.face(f.char_id)
		if not fc.is_empty():
			var pw := ps * 77.0 / 128.0
			draw.draw_texture_rect_region(fc[0], Rect2(Vector2(14.0 if i == 0 else vs.x - 14.0 - pw, 10.0), Vector2(pw, ps)), fc[1])
		var x := (30.0 + ps * 0.6 if not fc.is_empty() else 40.0) if i == 0 else vs.x - (30.0 + ps * 0.6 if not fc.is_empty() else 40.0) - w
		var y := 34.0
		var nm: String = Roster.display_name(f.char_id) + (" (CPU)" if fight.cpu_flags[i] else "")
		draw.draw_string(font, Vector2(x if i == 0 else x + w - font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x, y + 26), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.95, 0.75))
		var by := y + 36.0
		draw.draw_rect(Rect2(x - 3, by - 3, w + 6, 30), Color(0, 0, 0, 0.75))
		var frac := float(f.hp) / Rules.MAX_HP
		var bw := w * frac
		var bx := x if i == 1 else x + w - bw
		var col := Color(1.0, 0.82, 0.15).lerp(Color(1.0, 0.25, 0.1), 1.0 - frac)
		draw.draw_rect(Rect2(bx, by, bw, 24), col)
		draw.draw_rect(Rect2(bx, by, bw, 8), Color(1, 1, 1, 0.35))
		# gem slots
		for g in 3:
			var gx := (x + w - 18 - g * 34) if i == 0 else (x + 18 + g * 34)
			var c := Vector2(gx, by + 46)
			var pts := PackedVector2Array([c + Vector2(0, -13), c + Vector2(11, 0), c + Vector2(0, 13), c + Vector2(-11, 0)])
			var filled := g < f.gems or f.powered
			draw.draw_colored_polygon(pts, Gem.COLORS[g] if filled else Color(0.15, 0.15, 0.2, 0.8))
			pts.append(pts[0]); draw.draw_polyline(pts, Color(1, 1, 1, 0.8), 2.0)
		# power gauge
		if f.powered:
			var gw := w * 0.7 * f.gauge / Rules.GAUGE_MAX
			var gx2 := x if i == 0 else x + w * 0.3
			draw.draw_rect(Rect2(gx2 - 2, by + 66, w * 0.7 + 4, 16), Color(0, 0, 0, 0.7))
			draw.draw_rect(Rect2(gx2 if i == 0 else gx2 + w * 0.7 - gw, by + 68, gw, 12), Color(0.4, 0.85, 1.0))
			draw.draw_string(font, Vector2(gx2, by + 102), "POWER", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.6, 0.9, 1))
		# round wins
		for r in Rules.ROUNDS_TO_WIN:
			var rx := (x + 12 + r * 26) if i == 0 else (x + w - 12 - r * 26)
			draw.draw_circle(Vector2(rx, by + 46), 9, Color(1, 0.8, 0.2) if r < fight.wins[i] else Color(0.2, 0.2, 0.25))
	var tstr := "%02d" % int(ceil(fight.timer))
	var ts := font.get_string_size(tstr, HORIZONTAL_ALIGNMENT_CENTER, -1, 64)
	draw.draw_string(font, Vector2(vs.x * 0.5 - ts.x * 0.5, 96), tstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(1, 1, 1))
	if msg_t > 0.0:
		var a := clampf(msg_t / 0.25, 0.0, 1.0)
		var s := 120 if msg.length() < 8 else (96 if msg.length() < 14 else 80)
		var ms := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, s)
		var p := Vector2(vs.x * 0.5 - ms.x * 0.5, vs.y * msg_y)
		draw.draw_string_outline(font, p, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, s, 14, Color(0.1, 0.05, 0.0, a))
		draw.draw_string(font, p, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(1.0, 0.85, 0.25, a))

## The arcade's elapsed TIME (the original's top-left M'SS"hh: fight frames of the whole run until each KO / TIME call)
func _draw_elapsed(fg: Fight, font: Font) -> void:
	var f := fg.elapsed_f
	var t := "TIME  %d'%02d\"%02d" % [f / 3600, (f / 60) % 60, (f % 60) * 100 / 60]
	var px := 30.0 + 118.0 * 0.6 if fg.phase == Fight.R.FIGHT else 40.0
	draw.draw_string_outline(font, Vector2(px, 26), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0))
	draw.draw_string(font, Vector2(px, 26), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.2))

## Battle Royale: one compact panel per fighter across the top (portrait, name, health, stones, power gauge, round wins
## of his team); 2v2 panels are edged in their team colour; a fighter who's down is greyed out.
const TEAM_COLS := [Color(1.0, 0.3, 0.25), Color(0.3, 0.55, 1.0)]

func _draw_multi() -> void:
	var vs := draw.size
	var font := ThemeDB.fallback_font
	var n: int = fight.fighters.size()
	var pw := vs.x * 0.215; var gap := (vs.x - pw * n) / (n + 1)
	var teams_on := false
	for i in n: if int(fight.teams[i]) != i: teams_on = true
	for i in n:
		var f: Fighter = fight.fighters[i]
		var x := gap + i * (pw + gap); var y := 12.0
		var down := f.hp <= 0
		var dim := Color(1, 1, 1, 0.45) if down else Color.WHITE
		var tc: Color = TEAM_COLS[clampi(int(fight.teams[i]), 0, 1)] if teams_on else Color(1, 0.85, 0.3)
		draw.draw_rect(Rect2(x - 4, y - 4, pw + 8, 112), Color(0, 0, 0, 0.55))
		draw.draw_rect(Rect2(x - 4, y - 4, pw + 8, 112), tc * Color(1, 1, 1, 0.9), false, 3.0)
		var fc := Roster.face(f.char_id)
		var px := x
		if not fc.is_empty():
			draw.draw_texture_rect_region(fc[0], Rect2(Vector2(x, y), Vector2(62, 102)), fc[1], dim)
			px = x + 68
		var bw := pw - (px - x) - 4
		var nm: String = "P%d %s%s" % [i + 1, Roster.display_name(f.char_id), " (CPU)" if fight.cpu_flags[i] else ""]
		draw.draw_string(font, Vector2(px, y + 22), nm, HORIZONTAL_ALIGNMENT_LEFT, bw, 20, Color(1, 0.95, 0.75) * dim)
		draw.draw_rect(Rect2(px, y + 32, bw, 18), Color(0, 0, 0, 0.8))
		var frac := float(f.hp) / Rules.MAX_HP
		draw.draw_rect(Rect2(px, y + 32, bw * frac, 18), Color(1.0, 0.82, 0.15).lerp(Color(1.0, 0.25, 0.1), 1.0 - frac))
		for g in 3:
			var c := Vector2(px + 10 + g * 24, y + 66)
			var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(8, 0), c + Vector2(0, 9), c + Vector2(-8, 0)])
			draw.draw_colored_polygon(pts, Gem.COLORS[g] if (g < f.gems or f.powered) else Color(0.15, 0.15, 0.2, 0.8))
		if f.powered:
			draw.draw_rect(Rect2(px + 80, y + 60, (bw - 84) * f.gauge / Rules.GAUGE_MAX, 10), Color(0.4, 0.85, 1.0))
		var tw: int = int(fight.wins[int(fight.teams[i])]) if int(fight.teams[i]) < fight.wins.size() else 0
		for r in Rules.ROUNDS_TO_WIN:
			draw.draw_circle(Vector2(px + 8 + r * 20, y + 92), 6, Color(1, 0.8, 0.2) if r < tw else Color(0.2, 0.2, 0.25))
		if down:
			draw.draw_string_outline(font, Vector2(px + bw * 0.45, y + 98), "K.O.", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0))
			draw.draw_string(font, Vector2(px + bw * 0.45, y + 98), "K.O.", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(1, 0.3, 0.2))
	var tstr := "%02d" % int(ceil(fight.timer))
	var ts := font.get_string_size(tstr, HORIZONTAL_ALIGNMENT_CENTER, -1, 56)
	draw.draw_string_outline(font, Vector2(vs.x * 0.5 - ts.x * 0.5, 180), tstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, 8, Color(0, 0, 0))
	draw.draw_string(font, Vector2(vs.x * 0.5 - ts.x * 0.5, 180), tstr, HORIZONTAL_ALIGNMENT_LEFT, -1, 56, Color(1, 1, 1))
	_draw_msg(vs, font)

func _draw_msg(vs: Vector2, font: Font) -> void:
	if msg_t > 0.0:
		var a := clampf(msg_t / 0.25, 0.0, 1.0)
		var s := 120 if msg.length() < 8 else (96 if msg.length() < 14 else 80)
		var ms := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_CENTER, -1, s)
		var p := Vector2(vs.x * 0.5 - ms.x * 0.5, vs.y * msg_y)
		draw.draw_string_outline(font, p, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, s, 14, Color(0.1, 0.05, 0.0, a))
		draw.draw_string(font, p, msg, HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(1.0, 0.85, 0.25, a))
