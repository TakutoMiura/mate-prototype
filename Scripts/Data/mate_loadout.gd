class_name MateLoadout
extends Resource

@export var mate_id: String = ""
@export var shield_id: String = ""
@export var main_arm_id: String = ""
@export var back_unit_id: String = ""
@export var expansion_id: String = ""


func resolve(catalog: EquipmentCatalog) -> Dictionary:
	return {
		"mate": catalog.get_mate(mate_id),
		"shield": catalog.get_shield(shield_id),
		"main_arm": catalog.get_main_arm(main_arm_id),
		"back_unit": catalog.get_back_unit(back_unit_id),
		"expansion": catalog.get_expansion(expansion_id),
	}


func total_weight(catalog: EquipmentCatalog) -> float:
	var parts := resolve(catalog)
	var mate: MateDefinition = parts["mate"]
	if mate == null:
		return 0.0
	var result := mate.base_weight
	for slot in ["shield", "main_arm", "back_unit", "expansion"]:
		var part: PartDefinition = parts[slot]
		if part != null:
			result += part.weight
	return result


func is_compatible(catalog: EquipmentCatalog) -> bool:
	var parts := resolve(catalog)
	var mate: MateDefinition = parts["mate"]
	if mate == null:
		return false
	for slot in ["shield", "main_arm", "back_unit", "expansion"]:
		var part: PartDefinition = parts[slot]
		if part != null and not part.compatible_mate_ids.has(mate.id):
			return false
	return true
