class_name CommunicationPanel
extends PanelContainer

const PANEL_SURFACE := Color("#202C33")
const TEXT_COLOR := Color("#F0F3F5")
var _entries: Array[CommunicationEntry] = []
var _latest_message: Label
var _speaker_icon: SpeakerPortrait
var _history_popup: PopupPanel
var _history_list: VBoxContainer
var _history_scroll: ScrollContainer


func _ready() -> void:
	custom_minimum_size = Vector2(0, 50)
	_build()


func add_entry(entry: CommunicationEntry) -> void:
	if entry == null:
		return
	_entries.append(entry)
	_latest_message.text = entry.text
	_speaker_icon.set_portrait(entry.speaker_portrait)
	if _history_popup.visible:
		_append_history_entry(entry)


func _build() -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_SURFACE
	panel_style.set_corner_radius_all(4)
	panel_style.set_border_width_all(1)
	panel_style.border_color = Color("#4D6068")
	add_theme_stylebox_override("panel", panel_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)

	var title := Label.new()
	title.text = "COMMS"
	title.custom_minimum_size = Vector2(64, 0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#91B8C5"))
	title.add_theme_font_size_override("font_size", 13)
	row.add_child(title)
	_speaker_icon = SpeakerPortrait.new()
	_speaker_icon.custom_minimum_size = Vector2(36, 36)
	_speaker_icon.tooltip_text = "発話者"
	row.add_child(_speaker_icon)

	_latest_message = Label.new()
	_latest_message.text = "通信待機中"
	_latest_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_latest_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_latest_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_latest_message.add_theme_color_override("font_color", TEXT_COLOR)
	_latest_message.add_theme_font_size_override("font_size", 14)
	row.add_child(_latest_message)

	var history_button := Button.new()
	# TODO: replace this temporary glyph with the shared communications-history icon.
	history_button.text = "≡"
	history_button.tooltip_text = "通信履歴"
	history_button.custom_minimum_size = Vector2(48, 42)
	history_button.add_theme_font_size_override("font_size", 22)
	history_button.pressed.connect(_show_history)
	row.add_child(history_button)

	_history_popup = PopupPanel.new()
	_history_popup.unresizable = false
	_history_popup.size = Vector2i(680, 440)
	add_child(_history_popup)

	var popup_margin := MarginContainer.new()
	popup_margin.add_theme_constant_override("margin_left", 16)
	popup_margin.add_theme_constant_override("margin_right", 16)
	popup_margin.add_theme_constant_override("margin_top", 12)
	popup_margin.add_theme_constant_override("margin_bottom", 12)
	popup_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_history_popup.add_child(popup_margin)

	var popup_column := VBoxContainer.new()
	popup_column.add_theme_constant_override("separation", 10)
	popup_margin.add_child(popup_column)

	var popup_header := HBoxContainer.new()
	popup_column.add_child(popup_header)
	var popup_title := Label.new()
	popup_title.text = "COMMUNICATION LOG"
	popup_title.add_theme_color_override("font_color", TEXT_COLOR)
	popup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_header.add_child(popup_title)
	var close_button := Button.new()
	close_button.text = "×"
	close_button.pressed.connect(_history_popup.hide)
	popup_header.add_child(close_button)

	_history_scroll = ScrollContainer.new()
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	popup_column.add_child(_history_scroll)
	_history_list = VBoxContainer.new()
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_scroll.add_child(_history_list)
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = PANEL_SURFACE
	popup_style.set_corner_radius_all(4)
	_history_popup.add_theme_stylebox_override("panel", popup_style)
	_refresh_history()


func _show_history() -> void:
	_refresh_history()
	_history_popup.popup_centered()
	_scroll_to_latest.call_deferred()


func _refresh_history() -> void:
	if not is_instance_valid(_history_list):
		return
	for child in _history_list.get_children():
		_history_list.remove_child(child)
		child.queue_free()
	for entry in _entries:
		_append_history_entry(entry)
	if _entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "履歴はありません"
		empty_label.add_theme_color_override("font_color", TEXT_COLOR)
		_history_list.add_child(empty_label)


func _append_history_entry(entry: CommunicationEntry) -> void:
	if _entries.size() == 1 and _history_list.get_child_count() == 1:
		var empty_label := _history_list.get_child(0)
		if empty_label is Label and empty_label.text == "履歴はありません":
			_history_list.remove_child(empty_label)
			empty_label.queue_free()
	var message_row := HBoxContainer.new()
	message_row.add_theme_constant_override("separation", 10)
	message_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_child(message_row)
	var speaker_icon := SpeakerPortrait.new()
	speaker_icon.set_portrait(entry.speaker_portrait)
	speaker_icon.custom_minimum_size = Vector2(32, 32)
	message_row.add_child(speaker_icon)
	var message := Label.new()
	message.text = entry.text
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.add_theme_color_override("font_color", TEXT_COLOR)
	message.add_theme_font_size_override("font_size", 14)
	message_row.add_child(message)
	if _history_popup.visible:
		_scroll_to_latest.call_deferred()


func _scroll_to_latest() -> void:
	_history_scroll.scroll_vertical = int(_history_scroll.get_v_scroll_bar().max_value)
