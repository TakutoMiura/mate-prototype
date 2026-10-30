class_name HudGauge
extends Control

const BACKGROUND := Color("#080C0E")
const FILL := Color("#91B8C5")
const TEXT_DARK := Color("#080C0E")
const TEXT_LIGHT := Color("#F0F3F5")
const FONT_SIZE := 10

var current_value: float = 0.0
var maximum_value: float = 0.0
var unavailable: bool = false
var fill_color: Color = FILL
var _filled_text_clip: Control
var _empty_text_clip: Control
var _filled_text: Label
var _empty_text: Label


func _ready() -> void:
	custom_minimum_size = Vector2(100, 14)
	_filled_text_clip = _create_text_clip(TEXT_DARK)
	_empty_text_clip = _create_text_clip(TEXT_LIGHT)
	resized.connect(_sync_text_layers)
	_update_text()
	_sync_text_layers()
	queue_redraw()


func set_values(current: float, maximum: float, is_unavailable: bool = false, gauge_fill_color: Color = FILL) -> void:
	current_value = current
	maximum_value = maximum
	unavailable = is_unavailable
	fill_color = gauge_fill_color
	_update_text()
	_sync_text_layers()
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, BACKGROUND)
	if not unavailable and maximum_value > 0.0:
		var ratio := clampf(current_value / maximum_value, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), fill_color)


func _create_text_clip(color: Color) -> Control:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(label)
	if color == TEXT_DARK:
		_filled_text = label
	else:
		_empty_text = label
	return clip


func _update_text() -> void:
	var text := "N/A" if unavailable or maximum_value <= 0.0 else "%s/%s" % [_format_value(current_value), _format_value(maximum_value)]
	if is_instance_valid(_filled_text):
		_filled_text.text = text
	if is_instance_valid(_empty_text):
		_empty_text.text = text


func _sync_text_layers() -> void:
	if not is_instance_valid(_filled_text_clip) or not is_instance_valid(_empty_text_clip):
		return
	var ratio := 0.0
	if not unavailable and maximum_value > 0.0:
		ratio = clampf(current_value / maximum_value, 0.0, 1.0)
	var filled_width := size.x * ratio
	_filled_text_clip.position = Vector2.ZERO
	_filled_text_clip.size = Vector2(filled_width, size.y)
	_empty_text_clip.position = Vector2(filled_width, 0.0)
	_empty_text_clip.size = Vector2(size.x - filled_width, size.y)
	_filled_text.position = Vector2.ZERO
	_filled_text.size = size
	_empty_text.position = Vector2(-filled_width, 0.0)
	_empty_text.size = size


func _format_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return "%.1f" % value
