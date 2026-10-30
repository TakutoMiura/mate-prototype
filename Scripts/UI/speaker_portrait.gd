class_name SpeakerPortrait
extends Control

const PANEL_COLOR := Color("#202C33")
const FACE_COLOR := Color("#91B8C5")
const ACCENT_COLOR := Color("#806A32")
const LINE_COLOR := Color("#F0F3F5")

var portrait: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_portrait(texture: Texture2D) -> void:
	portrait = texture
	queue_redraw()


func _draw() -> void:
	if portrait != null:
		draw_texture_rect(portrait, Rect2(Vector2.ZERO, size), false)
		return

	draw_rect(Rect2(Vector2.ZERO, size), PANEL_COLOR, true)
	var center := Vector2(size.x * 0.48, size.y * 0.38)
	var head_radius := minf(size.x, size.y) * 0.19
	draw_circle(center, head_radius, FACE_COLOR)
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x * 0.20, size.y * 0.90),
		Vector2(size.x * 0.27, size.y * 0.70),
		Vector2(size.x * 0.48, size.y * 0.61),
		Vector2(size.x * 0.70, size.y * 0.70),
		Vector2(size.x * 0.77, size.y * 0.90),
	]), FACE_COLOR)
	draw_arc(center, head_radius * 1.45, PI, TAU, 24, ACCENT_COLOR, maxf(1.5, size.x * 0.06), true)
	draw_rect(Rect2(Vector2(size.x * 0.27, size.y * 0.35), Vector2(size.x * 0.09, size.y * 0.22)), ACCENT_COLOR)
	draw_rect(Rect2(Vector2(size.x * 0.60, size.y * 0.35), Vector2(size.x * 0.09, size.y * 0.22)), ACCENT_COLOR)
	draw_line(Vector2(size.x * 0.66, size.y * 0.55), Vector2(size.x * 0.76, size.y * 0.63), LINE_COLOR, maxf(1.0, size.x * 0.035), true)
	draw_circle(Vector2(size.x * 0.76, size.y * 0.63), maxf(1.0, size.x * 0.045), LINE_COLOR)
