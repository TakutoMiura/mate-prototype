class_name MateUnitState
extends Resource

@export var loadout: MateLoadout
@export var current_hp: float = 0.0:
	set(value):
		if is_equal_approx(current_hp, value):
			return
		current_hp = value
		emit_changed()
@export var current_shield_hp: float = 0.0:
	set(value):
		if is_equal_approx(current_shield_hp, value):
			return
		current_shield_hp = value
		emit_changed()
@export var current_back_unit_ammo: float = 0.0:
	set(value):
		if is_equal_approx(current_back_unit_ammo, value):
			return
		current_back_unit_ammo = value
		emit_changed()


func initialize_full(catalog: EquipmentCatalog) -> bool:
	if loadout == null or catalog == null:
		return false
	var parts := loadout.resolve(catalog)
	var mate: MateDefinition = parts["mate"]
	if mate == null:
		return false
	var shield: ShieldDefinition = parts["shield"]
	var back_unit: BackUnitDefinition = parts["back_unit"]
	current_hp = mate.durability_max
	current_shield_hp = shield.durability_max if shield != null else 0.0
	current_back_unit_ammo = back_unit.ammo_capacity if back_unit != null else 0.0
	return true
