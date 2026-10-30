class_name CombatHud
extends Control

signal squad_focus_requested(squad_number: int)
signal squad_order_change_requested(squad_number: int, order_id: String)

const PLACEHOLDER_PORTRAIT := preload("res://Assets/mate_face_placeholder.svg")
@export var show_preview_data: bool = false

@export var directive_library: DirectiveLibrary

var _squads: Array[HudSquadData] = []
var _selected_squad: int = 0
var _squad_row: HBoxContainer
var _camera_status_label: Label
var _communication_panel: CommunicationPanel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	if directive_library == null:
		directive_library = _create_default_directive_library()
	else:
		_ensure_basic_directive()
	if show_preview_data:
		set_squads(_create_preview_squads())
		var preview_message := CommunicationEntry.new()
		preview_message.text = "デモ運転を開始します。各小隊の状態を確認してください。"
		append_communication(preview_message)
	elif _squads.is_empty():
		var empty_squads: Array[HudSquadData] = []
		set_squads(empty_squads)
	else:
		_refresh_squad_panels()


func set_squads(squads: Array[HudSquadData]) -> void:
	_squads.clear()
	for index in range(3):
		var squad: HudSquadData
		if index < squads.size() and squads[index] != null:
			squad = squads[index]
		else:
			squad = HudSquadData.new()
			squad.squad_number = index + 1
		_squads.append(squad)
	_refresh_squad_panels()


func set_directive_library(library: DirectiveLibrary) -> void:
	if library == null:
		return
	directive_library = library
	_ensure_basic_directive()
	_refresh_squad_panels()


func append_communication(entry: CommunicationEntry) -> void:
	if _communication_panel != null:
		_communication_panel.add_entry(entry)


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color("#10181D")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	margin.add_child(layout)

	_squad_row = HBoxContainer.new()
	_squad_row.add_theme_constant_override("separation", 10)
	_squad_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_squad_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_squad_row.size_flags_stretch_ratio = 1.6
	layout.add_child(_squad_row)

	var battlefield := PanelContainer.new()
	battlefield.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield.size_flags_stretch_ratio = 4.4
	battlefield.add_theme_stylebox_override("panel", _panel_style(Color("#18242A")))
	layout.add_child(battlefield)

	var battlefield_layout := VBoxContainer.new()
	battlefield_layout.add_theme_constant_override("separation", 2)
	battlefield.add_child(battlefield_layout)

	var camera_title := Label.new()
	camera_title.text = "FIELD CAMERA"
	camera_title.add_theme_color_override("font_color", Color("#91B8C5"))
	camera_title.add_theme_font_size_override("font_size", 11)
	battlefield_layout.add_child(camera_title)

	_camera_status_label = Label.new()
	_camera_status_label.text = "CAMERA OFFLINE  /  DEMO MODE"
	_camera_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camera_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_camera_status_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_camera_status_label.add_theme_color_override("font_color", Color("#A9BAC1"))
	_camera_status_label.add_theme_font_size_override("font_size", 18)
	battlefield_layout.add_child(_camera_status_label)

	_communication_panel = CommunicationPanel.new()
	layout.add_child(_communication_panel)


func _refresh_squad_panels() -> void:
	if _squad_row == null:
		return
	for child in _squad_row.get_children():
		_squad_row.remove_child(child)
		child.queue_free()
	for squad in _squads:
		var panel := SquadPanel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.squad_selected.connect(_on_squad_selected)
		panel.order_requested.connect(_on_order_requested)
		_squad_row.add_child(panel)
		panel.set_squad_data(squad, squad.squad_number == _selected_squad, directive_library)


func _on_squad_selected(squad_number: int) -> void:
	_selected_squad = squad_number
	_refresh_squad_panels()
	_camera_status_label.text = "CAMERA FOCUS  /  SQUAD %02d" % squad_number
	squad_focus_requested.emit(squad_number)


func _on_order_requested(squad_number: int, order_id: String) -> void:
	for squad in _squads:
		if squad.squad_number == squad_number:
			squad.active_order_id = order_id
			break
	squad_order_change_requested.emit(squad_number, order_id)


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.border_color = Color("#4D6068")
	return style


func _create_preview_squads() -> Array[HudSquadData]:
	var squads: Array[HudSquadData] = []
	squads.append(_make_preview_squad(1, _basic_directive_id(), [
		_make_preview_mate("MATE-01", 150, 300, 100, 200, true, 18, 24),
		_make_preview_mate("MATE-02", 230, 300, 170, 200, true, 15, 24),
		_make_preview_mate("MATE-03", 260, 300, 160, 200, false, 0, 0),
	]))
	squads.append(_make_preview_squad(2, "MOVE", [
		_make_preview_mate("MATE-04", 0, 300, 0, 200, true, 6, 24),
		_make_preview_mate("MATE-05", 180, 300, 100, 200, true, 12, 24),
		_make_preview_mate("MATE-06", 190, 300, 100, 200, true, 10, 24),
	]))
	squads.append(_make_preview_squad(3, "HOLD", [
		_make_preview_mate("MATE-07", 0, 300, 0, 200, true, 4, 24),
		_make_preview_mate("MATE-08", 0, 300, 0, 200, true, 0, 24),
		_make_preview_mate("MATE-09", 170, 300, 60, 200, true, 6, 24),
	]))
	return squads


func _make_preview_squad(number: int, order_id: String, mates: Array) -> HudSquadData:
	var squad := HudSquadData.new()
	squad.squad_number = number
	squad.active_order_id = order_id
	squad.members.assign(mates)
	return squad


func _make_preview_mate(name: String, hp: float, max_hp: float, shield: float, max_shield: float, back_unit: bool, ammo: float, max_ammo: float) -> HudMateData:
	var mate := HudMateData.new()
	_fill_preview_mate(mate, name, hp, max_hp, shield, max_shield, back_unit, ammo, max_ammo)
	return mate


func _fill_preview_mate(mate: HudMateData, name: String, hp: float, max_hp: float, shield: float, max_shield: float, back_unit: bool, ammo: float, max_ammo: float) -> void:
	mate.display_name = name
	mate.current_hp = hp
	mate.maximum_hp = max_hp
	mate.current_shield_hp = shield
	mate.maximum_shield_hp = max_shield
	mate.has_back_unit = back_unit
	mate.current_ammo = ammo
	mate.maximum_ammo = max_ammo
	mate.portrait = PLACEHOLDER_PORTRAIT


func _create_default_directive_library() -> DirectiveLibrary:
	var library := DirectiveLibrary.new()
	directive_library = library
	_ensure_basic_directive()
	return library


func _ensure_basic_directive() -> void:
	if directive_library == null:
		return
	for directive in directive_library.directives:
		if directive != null and directive.behavior_profile == DirectiveDefinition.BASIC_BEHAVIOR_PROFILE:
			directive.identifier = "directive.basic"
			if directive.display_name.is_empty():
				directive.display_name = "BASIC DIRECTIVE"
			return
	var basic := DirectiveDefinition.new()
	basic.identifier = "directive.basic"
	basic.display_name = "BASIC DIRECTIVE"
	basic.behavior_profile = DirectiveDefinition.BASIC_BEHAVIOR_PROFILE
	directive_library.directives.append(basic)


func _basic_directive_id() -> String:
	for directive in directive_library.directives:
		if directive != null and directive.behavior_profile == DirectiveDefinition.BASIC_BEHAVIOR_PROFILE:
			return directive.identifier
	return "directive.basic"
