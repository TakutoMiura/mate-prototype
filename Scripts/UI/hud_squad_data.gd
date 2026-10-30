class_name HudSquadData
extends Resource

@export_range(1, 3, 1) var squad_number: int = 1
@export var members: Array[HudMateData] = []
@export var active_order_id: String = "directive.basic"


func display_title() -> String:
	return "SQUAD %02d" % squad_number
