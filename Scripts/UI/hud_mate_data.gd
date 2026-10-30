class_name HudMateData
extends Resource

@export var display_name: String = "MATE"
@export var loadout: MateLoadout
@export var unit_state: Resource
@export var portrait: Texture2D
@export var current_hp: float = 0.0
@export var maximum_hp: float = 0.0
@export var current_shield_hp: float = 0.0
@export var maximum_shield_hp: float = 0.0
@export var has_back_unit: bool = false
@export var current_ammo: float = 0.0
@export var maximum_ammo: float = 0.0
var _catalog: EquipmentCatalog


func durability_ratio() -> float:
	var maximum := maximum_hp + maximum_shield_hp
	if maximum <= 0.0:
		return -1.0
	return (current_hp + current_shield_hp) / maximum


func has_ammo_display() -> bool:
	return has_back_unit and maximum_ammo > 0.0


func configure_from_state(value: Resource, catalog: EquipmentCatalog) -> bool:
	if unit_state != null and unit_state.changed.is_connected(_sync_from_unit_state):
		unit_state.changed.disconnect(_sync_from_unit_state)
	unit_state = value
	_catalog = catalog
	if unit_state == null or _catalog == null:
		return false
	var state: Variant = unit_state
	if state.loadout == null or _catalog.get_mate(state.loadout.mate_id) == null:
		return false
	unit_state.changed.connect(_sync_from_unit_state)
	_sync_from_unit_state()
	return true


func _sync_from_unit_state() -> void:
	if unit_state == null or _catalog == null:
		return
	var state: Variant = unit_state
	if state.loadout == null:
		return
	loadout = state.loadout
	var parts := loadout.resolve(_catalog)
	var mate: MateDefinition = parts["mate"]
	if mate == null:
		return
	display_name = mate.name
	current_hp = state.current_hp
	maximum_hp = mate.durability_max
	var shield: ShieldDefinition = parts["shield"]
	current_shield_hp = state.current_shield_hp
	maximum_shield_hp = shield.durability_max if shield != null else 0.0
	var back_unit: BackUnitDefinition = parts["back_unit"]
	has_back_unit = back_unit != null
	current_ammo = state.current_back_unit_ammo
	maximum_ammo = back_unit.ammo_capacity if back_unit != null else 0.0
	emit_changed()
