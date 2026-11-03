class_name HintBar
extends Control
## Bottom bar of PS5 button glyphs with labels.

var items := []   # [[glyph, text], ...]

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var x := 60.0
	for it in items:
		UI.glyph(self, it[0], Vector2(x, 30), 13)
		draw_string(font, Vector2(x + 26, 41), it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.9))
		x += 60 + font.get_string_size(it[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 30
