class_name CombatHud
extends Control

signal squad_focus_requested(squad_number: int)
signal squad_order_change_requested(squad_number: int, order_id: String)

const PLACEHOLDER_PORTRAIT := preload("res://Assets/mate_face_placeholder.svg")
const TEST_FIELD_SCENE := preload("res://Scenes/test_field.tscn")
const UNIT_STATUS_OVERLAY_SCRIPT := preload("res://Scripts/UI/unit_status_overlay.gd")
@export var show_preview_data: bool = false

@export var directive_library: DirectiveLibrary

var _squads: Array[HudSquadData] = []
var _selected_squad: int = 0
var _squad_row: HBoxContainer
var _camera_status_label: Label
var _communication_panel: CommunicationPanel
var _test_field: TestField
var _unit_status_overlay: UnitStatusOverlay


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

	var viewport_overlay := Control.new()
	viewport_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield_layout.add_child(viewport_overlay)
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "TestFieldViewportContainer"
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_overlay.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.name = "TestFieldViewport"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_container.add_child(viewport)
	_test_field = TEST_FIELD_SCENE.instantiate() as TestField
	_test_field.squad_selection_requested.connect(_on_squad_selected)
	_test_field.walking_comparison_changed.connect(_on_walking_comparison_changed)
	viewport.add_child(_test_field)
	_test_field.prepare()
	_unit_status_overlay = UNIT_STATUS_OVERLAY_SCRIPT.new() as UnitStatusOverlay
	viewport.add_child(_unit_status_overlay)
	_unit_status_overlay.configure(_test_field)

	_camera_status_label = Label.new()
	_camera_status_label.text = "TEST FIELD  /  FOCUS --  /  WALK COMPARE ON [C]"
	_camera_status_label.position = Vector2(8, 6)
	_camera_status_label.size = Vector2(390, 22)
	_camera_status_label.add_theme_color_override("font_color", Color("#D7E0E3"))
	_camera_status_label.add_theme_font_size_override("font_size", 11)
	_camera_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_overlay.add_child(_camera_status_label)

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
	_refresh_field_status()
	if _test_field != null:
		_test_field.focus_squad(squad_number)
	if _unit_status_overlay != null and squad_number > 0 and squad_number <= _squads.size():
		_unit_status_overlay.set_selected_squad(squad_number, _squads[squad_number - 1].members)
	squad_focus_requested.emit(squad_number)


func _on_walking_comparison_changed(enabled: bool) -> void:
	_refresh_field_status()


func _refresh_field_status() -> void:
	if _camera_status_label == null:
		return
	var focus_text := "--" if _selected_squad <= 0 else "%02d" % _selected_squad
	var compare_text := "ON" if _test_field == null or _test_field.walking_comparison_enabled else "OFF"
	_camera_status_label.text = "TEST FIELD  /  FOCUS %s  /  WALK COMPARE %s [C]" % [focus_text, compare_text]


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
	var catalog: EquipmentCatalog = _test_field.equipment_catalog if _test_field != null else null
	if catalog == null or _test_field == null:
		push_error("Preview HUD requires a prepared test field.")
		return squads
	for squad_index in range(3):
		var members: Array[HudMateData] = []
		for unit_state in _test_field.get_squad_states(squad_index + 1):
			var mate := HudMateData.new()
			if not mate.configure_from_state(unit_state, catalog):
				push_warning("Could not read sample unit state for squad %d." % (squad_index + 1))
				continue
			mate.portrait = PLACEHOLDER_PORTRAIT
			members.append(mate)
		squads.append(_make_preview_squad(squad_index + 1, _basic_directive_id(), members))
	return squads


func _make_preview_squad(number: int, order_id: String, mates: Array) -> HudSquadData:
	var squad := HudSquadData.new()
	squad.squad_number = number
	squad.active_order_id = order_id
	squad.members.assign(mates)
	return squad


func _create_default_directive_library() -> DirectiveLibrary:
	var library := DirectiveLibrary.new()
	directive_library = library
	_ensure_basic_directive()
	return library


func _ensure_basic_directive() -> void:
	if directive_library == null:
		return
	directive_library.ensure_unique_identifiers()
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
