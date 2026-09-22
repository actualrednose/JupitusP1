extends RefCounted
class_name CombatantState

enum Team {
	PLAYER,
	ENEMY,
}

var definition: CombatantDefinition
var team: Team

var current_hp: int
var current_tempo: int

var is_guarding: bool = false
var is_preparing_power_attack: bool = false
var power_attack_disrupted: bool = false
var pending_power_attack: AbilityDefinition = null
var active_statuses: Dictionary = {}


func _init(
	source_definition: CombatantDefinition,
	source_team: Team
) -> void:
	definition = source_definition
	team = source_team
	current_hp = definition.max_hp
	current_tempo = 0


func is_defeated() -> bool:
	return current_hp <= 0


func is_damaged() -> bool:
	return current_hp * 2 < definition.max_hp


func can_use_ability(ability: AbilityDefinition) -> bool:
	if ability == null:
		return false

	if is_defeated():
		return false

	return current_tempo >= ability.tempo_cost


func spend_tempo(amount: int) -> bool:
	if amount < 0:
		push_warning(
			"CombatantState: cannot spend a negative Tempo amount"
		)
		return false

	if current_tempo < amount:
		return false

	current_tempo -= amount
	return true


func gain_tempo(amount: int) -> void:
	if amount <= 0 or is_defeated():
		return

	current_tempo = mini(
		current_tempo + amount,
		definition.max_tempo
	)


func change_tempo(amount: int) -> int:
	if is_defeated():
		return 0

	var previous_tempo := current_tempo
	current_tempo = clampi(
		current_tempo + amount,
		0,
		definition.max_tempo
	)
	return current_tempo - previous_tempo


func begin_turn() -> void:
	# Guard lasts until the next turn begins.
	is_guarding = false
	_tick_statuses()


func choose_guard() -> void:
	is_guarding = true


func receive_damage(
	raw_damage: int,
	tempo_gain: int = 5
) -> int:
	if is_defeated():
		return 0

	var final_damage: int = maxi(raw_damage, 0)

	if is_guarding:
		final_damage = maxi(
			ceili(final_damage / 2.0),
			1
		)
		tempo_gain *= 2

	current_hp = maxi(
		current_hp - final_damage,
		0
	)

	if final_damage > 0:
		gain_tempo(tempo_gain)

	return final_damage


func receive_healing(raw_amount: int) -> int:
	if is_defeated():
		return 0

	var previous_hp := current_hp
	current_hp = mini(
		current_hp + maxi(raw_amount, 0),
		definition.max_hp
	)
	return current_hp - previous_hp


func revive(raw_amount: int) -> int:
	if not is_defeated() or raw_amount <= 0:
		return 0

	current_hp = mini(
		maxi(raw_amount, 1),
		definition.max_hp
	)
	return current_hp


func apply_status(
	status: StatusEffectDefinition,
	duration_override: int = 0
) -> bool:
	if status == null or is_defeated():
		return false

	var duration := duration_override

	if duration <= 0:
		duration = status.duration_turns

	if duration <= 0:
		return false

	var status_id := status.status_id

	if active_statuses.has(status_id):
		var active_status: Dictionary = (
			active_statuses[status_id]
		)
		active_status["turns_remaining"] = maxi(
			int(active_status["turns_remaining"]),
			duration
		)

		if status.stackable:
			active_status["stacks"] = mini(
				int(active_status["stacks"]) + 1,
				status.max_stacks
			)

		active_statuses[status_id] = active_status
		return true

	active_statuses[status_id] = {
		"definition": status,
		"turns_remaining": duration,
		"stacks": 1,
	}
	return true


func cleanse_statuses(
	status: StatusEffectDefinition = null
) -> int:
	if status != null:
		if active_statuses.erase(status.status_id):
			return 1

		return 0

	var removed_count := active_statuses.size()
	active_statuses.clear()
	return removed_count


func has_status(status_id: StringName) -> bool:
	return active_statuses.has(status_id)


func _tick_statuses() -> void:
	var expired_statuses: Array[StringName] = []

	for status_id: StringName in active_statuses:
		var active_status: Dictionary = (
			active_statuses[status_id]
		)
		active_status["turns_remaining"] = (
			int(active_status["turns_remaining"]) - 1
		)

		if int(active_status["turns_remaining"]) <= 0:
			expired_statuses.append(status_id)
		else:
			active_statuses[status_id] = active_status

	for status_id in expired_statuses:
		active_statuses.erase(status_id)


func begin_power_attack(
	ability: AbilityDefinition
) -> void:
	if ability == null or not ability.is_power_attack:
		return

	is_preparing_power_attack = true
	power_attack_disrupted = false
	pending_power_attack = ability


func disrupt_power_attack() -> bool:
	if not is_preparing_power_attack:
		return false

	is_preparing_power_attack = false
	power_attack_disrupted = true
	pending_power_attack = null
	return true


func finish_power_attack() -> void:
	is_preparing_power_attack = false
	pending_power_attack = null
