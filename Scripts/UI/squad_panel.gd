class_name SquadPanel
extends PanelContainer

signal squad_selected(squad_number: int)
signal order_requested(squad_number: int, order_id: String)

const MATE_ICON := preload("res://Assets/mate_face_placeholder.svg")
const PANEL_SURFACE := Color("#202C33")
const NORMAL_COLOR := Color("#30566B")
const WARNING_COLOR := Color("#806A32")
const CRITICAL_COLOR := Color("#813D40")
const SELECTED_COLOR := Color("#F0F3F5")
const TEXT_COLOR := Color("#F0F3F5")
const HP_GAUGE_COLOR := Color("#69B85A")
const FIXED_ORDERS := ["HOLD", "MOVE"]

var _data: HudSquadData
var _selected := false
var _inactive := false
var _order_selector: OptionButton
var _order_ids: Array[String] = []
var _available_directives: Array[DirectiveDefinition] = []
var _content: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(280, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)


func set_squad_data(data: HudSquadData, selected: bool, directive_library: DirectiveLibrary) -> void:
	_data = data
	_selected = selected
	_order_ids.clear()
	_order_ids.append_array(FIXED_ORDERS)
	_available_directives.clear()
	if directive_library != null:
		for directive in directive_library.directives:
			if directive == null or directive.identifier.is_empty() or _order_ids.has(directive.identifier):
				continue
			_available_directives.append(directive)
			_order_ids.append(directive.identifier)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	if _data == null:
		return
	_inactive = _data.members.is_empty()

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_SURFACE if _inactive else _state_color(SquadCondition.classify(_data.members))
	style.set_corner_radius_all(4)
	style.set_border_width_all(3 if _selected else 1)
	style.border_color = SELECTED_COLOR if _selected else Color("#4D6068")
	add_theme_stylebox_override("panel", style)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 4)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(header)

	var title := Label.new()
	title.text = _data.display_title()
	title.add_theme_color_override("font_color", TEXT_COLOR)
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	_order_selector = OptionButton.new()
	_order_selector.add_theme_font_size_override("font_size", 12)
	for order_id in FIXED_ORDERS:
		_order_selector.add_item(order_id)
	for directive in _available_directives:
		var label := directive.display_name if not directive.display_name.is_empty() else directive.identifier
		_order_selector.add_item(label)
	_order_selector.item_selected.connect(_on_order_selected)
	_order_selector.disabled = _inactive
	if not _inactive:
		_order_selector.select(_order_ids.find(_data.active_order_id))
	header.add_child(_order_selector)

	if _inactive:
		var no_unit := Label.new()
		no_unit.text = "NO UNIT"
		no_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_unit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_unit.custom_minimum_size = Vector2(0, 88)
		no_unit.add_theme_color_override("font_color", TEXT_COLOR)
		no_unit.add_theme_font_size_override("font_size", 18)
		no_unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(no_unit)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return

	mouse_filter = Control.MOUSE_FILTER_STOP
	for mate in _data.members:
		_content.add_child(_create_mate_row(mate))


func _create_mate_row(mate: HudMateData) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 44)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait := TextureRect.new()
	portrait.texture = mate.portrait if mate.portrait != null else MATE_ICON
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(28, 28)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var gauges := VBoxContainer.new()
	gauges.add_theme_constant_override("separation", 1)
	gauges.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauges.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gauges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gauges)
	gauges.add_child(_create_gauge_row("HP", mate.current_hp, mate.maximum_hp, false, HP_GAUGE_COLOR))
	gauges.add_child(_create_gauge_row("SH", mate.current_shield_hp, mate.maximum_shield_hp, false, HP_GAUGE_COLOR))
	gauges.add_child(_create_gauge_row("AMMO", mate.current_ammo, mate.maximum_ammo, not mate.has_ammo_display()))
	return row


func _create_gauge_row(caption: String, current: float, maximum: float, unavailable: bool = false, fill_color: Color = HudGauge.FILL) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = caption
	label.custom_minimum_size = Vector2(34, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_font_size_override("font_size", 9)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var gauge := HudGauge.new()
	gauge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.set_values(current, maximum, unavailable, fill_color)
	row.add_child(gauge)
	return row


func _state_color(state: SquadCondition.State) -> Color:
	match state:
		SquadCondition.State.WARNING:
			return WARNING_COLOR
		SquadCondition.State.CRITICAL:
			return CRITICAL_COLOR
		_:
			return NORMAL_COLOR


func _on_gui_input(event: InputEvent) -> void:
	if _inactive or _data == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		squad_selected.emit(_data.squad_number)
		accept_event()


func _on_order_selected(index: int) -> void:
	if _inactive or index < 0 or index >= _order_ids.size():
		return
	order_requested.emit(_data.squad_number, _order_ids[index])
