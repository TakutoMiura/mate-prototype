class_name HudMateData
extends Resource

@export var display_name: String = "MATE"
@export var portrait: Texture2D
@export var current_hp: float = 0.0
@export var maximum_hp: float = 0.0
@export var current_shield_hp: float = 0.0
@export var maximum_shield_hp: float = 0.0
@export var has_back_unit: bool = false
@export var current_ammo: float = 0.0
@export var maximum_ammo: float = 0.0


func durability_ratio() -> float:
	var maximum := maximum_hp + maximum_shield_hp
	if maximum <= 0.0:
		return -1.0
	return (current_hp + current_shield_hp) / maximum


func has_ammo_display() -> bool:
	return has_back_unit and maximum_ammo > 0.0
