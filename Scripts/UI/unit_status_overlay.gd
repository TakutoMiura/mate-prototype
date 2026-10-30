class_name UnitStatusOverlay
extends Control

const WINDOW_SIZE := Vector2(110, 41)
const WINDOW_GAP := 5.0
const HP_FILL := Color("#69B85A")
const BAR_BACKGROUND := Color("#080C0E")
const TEXT_COLOR := Color("#F0F3F5")
const PANEL_COLORS := {
	SquadCondition.State.NORMAL: Color("#30566B"),
	SquadCondition.State.WARNING: Color("#806A32"),
	SquadCondition.State.CRITICAL: Color("#813D40"),
}

var _test_field: TestField
var _selected_squad := 0
var _members: Array[HudMateData] = []
var _previews: Array[MatePreview] = []
var _member_callbacks: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	resized.connect(_on_layout_changed)


func configure(test_field: TestField) -> void:
	_test_field = test_field
	if not _test_field.view_changed.is_connected(_on_layout_changed):
		_test_field.view_changed.connect(_on_layout_changed)


func set_selected_squad(squad_number: int, members: Array[HudMateData]) -> void:
	_clear_member_connections()
	_selected_squad = squad_number
	_members.assign(members)
	_previews = _test_field.get_squad_mates(squad_number) if _test_field != null and squad_number > 0 else []
	for member in _members:
		if member == null:
			continue
		var callback := _on_member_changed.bind(member)
		_member_callbacks[member.get_instance_id()] = callback
		member.changed.connect(callback)
	_on_layout_changed()


func _draw() -> void:
	if _selected_squad <= 0 or _test_field == null or _members.is_empty() or _previews.is_empty():
		return
	var camera := _test_field.get_camera()
	if camera == null:
		return

	var visible_units: Array[Dictionary] = []
	var unit_count := mini(_members.size(), _previews.size())
	var models_top := size.y
	var models_bottom := 0.0
	for index in range(unit_count):
		var mate := _previews[index]
		var anchor_3d := mate.global_position + Vector3(0, 1.8, 0)
		if camera.is_position_behind(anchor_3d):
			continue
		var anchor_2d := camera.unproject_position(anchor_3d)
		if anchor_2d.x < 0.0 or anchor_2d.x > size.x or anchor_2d.y < 0.0 or anchor_2d.y > size.y:
			continue
		var model_top := size.y
		var model_bottom := 0.0
		for local_corner in mate.get_status_bounds_corners():
			var corner := mate.to_global(local_corner)
			if camera.is_position_behind(corner):
				continue
			var projected_corner := camera.unproject_position(corner)
			model_top = minf(model_top, projected_corner.y)
			model_bottom = maxf(model_bottom, projected_corner.y)
		models_top = minf(models_top, model_top)
		models_bottom = maxf(models_bottom, model_bottom)
		visible_units.append({"point": anchor_2d, "model_top": model_top, "member": _members[index], "index": index})
	visible_units.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["point"].x < b["point"].x)
	if visible_units.is_empty():
		return

	var total_width := visible_units.size() * WINDOW_SIZE.x + (visible_units.size() - 1) * WINDOW_GAP
	var average_x := 0.0
	for unit in visible_units:
		average_x += unit["point"].x
	average_x /= visible_units.size()
	var first_x := clampf(average_x - total_width * 0.5, 8.0, maxf(8.0, size.x - total_width - 8.0))
	var window_y := models_top - WINDOW_SIZE.y - 14.0
	if window_y < 8.0 and models_bottom + WINDOW_SIZE.y + 14.0 <= size.y - 8.0:
		window_y = models_bottom + 14.0
	window_y = clampf(window_y, 8.0, maxf(8.0, size.y - WINDOW_SIZE.y - 8.0))
	var panel_color := _panel_color()
	var font := ThemeDB.fallback_font

	for index in range(visible_units.size()):
		var unit := visible_units[index]
		var window_position := Vector2(first_x + index * (WINDOW_SIZE.x + WINDOW_GAP), window_y)
		var line_end := Vector2(window_position.x + WINDOW_SIZE.x * 0.5, window_position.y + WINDOW_SIZE.y)
		draw_line(unit["point"], line_end, panel_color.lightened(0.35), 1.25, true)

	for index in range(visible_units.size()):
		var unit := visible_units[index]
		var window_position := Vector2(first_x + index * (WINDOW_SIZE.x + WINDOW_GAP), window_y)
		var member: HudMateData = unit["member"]
		_draw_unit_window(font, window_position, panel_color, member, int(unit["index"]) + 1)


func _draw_unit_window(font: Font, position: Vector2, panel_color: Color, member: HudMateData, unit_number: int) -> void:
	var window_rect := Rect2(position, WINDOW_SIZE)
	draw_rect(window_rect, Color("#10181D"))
	draw_rect(Rect2(position, Vector2(WINDOW_SIZE.x, 13)), panel_color)
	draw_rect(window_rect, panel_color.lightened(0.25), false, 1.0)
	draw_string(font, position + Vector2(5, 10), "UNIT %02d" % unit_number, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, TEXT_COLOR)
	_draw_bar(font, position, 16.0, "HP", member.current_hp, member.maximum_hp)
	_draw_bar(font, position, 27.0, "SH", member.current_shield_hp, member.maximum_shield_hp)


func _draw_bar(font: Font, window_position: Vector2, row_y: float, label: String, current: float, maximum: float) -> void:
	draw_string(font, window_position + Vector2(5, row_y + 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, TEXT_COLOR)
	var bar_rect := Rect2(window_position + Vector2(25, row_y), Vector2(78, 7))
	draw_rect(bar_rect, BAR_BACKGROUND)
	if maximum > 0.0:
		var ratio := clampf(current / maximum, 0.0, 1.0)
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), HP_FILL)


func _panel_color() -> Color:
	var state := SquadCondition.classify(_members)
	return PANEL_COLORS.get(state, PANEL_COLORS[SquadCondition.State.NORMAL])


func _clear_member_connections() -> void:
	for member in _members:
		if member == null:
			continue
		var callback: Callable = _member_callbacks.get(member.get_instance_id(), Callable())
		if callback.is_valid() and member.changed.is_connected(callback):
			member.changed.disconnect(callback)
	_member_callbacks.clear()


func _on_member_changed(_member: HudMateData) -> void:
	_on_layout_changed()


func _on_layout_changed() -> void:
	queue_redraw()
	if _test_field != null:
		_test_field.request_render()
