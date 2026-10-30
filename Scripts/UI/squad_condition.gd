class_name SquadCondition
extends RefCounted

enum State { NORMAL, WARNING, CRITICAL, INACTIVE }


static func classify(members: Array[HudMateData]) -> State:
	if members.is_empty():
		return State.INACTIVE

	var destroyed_count := 0
	var depleted_shields := 0
	var valid_ratios: Array[float] = []

	for mate in members:
		if mate.current_hp <= 0.0:
			destroyed_count += 1
		if mate.maximum_shield_hp > 0.0 and mate.current_shield_hp <= 0.0:
			depleted_shields += 1
		var ratio := mate.durability_ratio()
		if ratio >= 0.0:
			valid_ratios.append(ratio)

	if destroyed_count >= 2 or _all_below(valid_ratios, 0.40):
		return State.CRITICAL
	if destroyed_count >= 1 or depleted_shields >= 2 or _all_below(valid_ratios, 0.70):
		return State.WARNING
	return State.NORMAL


static func _all_below(ratios: Array[float], threshold: float) -> bool:
	if ratios.is_empty():
		return false
	for ratio in ratios:
		if ratio >= threshold:
			return false
	return true
