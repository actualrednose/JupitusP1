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


func _init(source_definition: CombatantDefinition, source_team: Team) -> void:
	definition = source_definition
	team = source_team
	current_hp = definition.max_hp
	current_tempo = 0


func is_defeated() -> bool:
	return current_hp <= 0


func can_use_ability(ability: AbilityDefinition) -> bool:
	if ability == null:
		return false

	if is_defeated():
		return false

	return current_tempo >= ability.tempo_cost


func spend_tempo(amount: int) -> bool:
	if amount < 0:
		push_warning("CombatantState: cannot spend a negative Tempo amount")
		return false

	if current_tempo < amount:
		return false

	current_tempo -= amount
	return true


func gain_tempo(amount: int) -> void:
	if amount <= 0 or is_defeated():
		return

	current_tempo = mini(current_tempo + amount, definition.max_tempo)


func begin_turn() -> void:
	# Guard lasts until the next turn begins.
	is_guarding = false


func choose_guard() -> void:
	is_guarding = true


func receive_damage(raw_damage: int, tempo_gain: int = 5) -> int:
	if is_defeated():
		return 0

	var final_damage: int = maxi(raw_damage, 0)

	if is_guarding:
		final_damage = maxi(ceili(final_damage / 2.0), 1)
		tempo_gain *= 2

	current_hp = maxi(current_hp - final_damage, 0)

	if final_damage > 0:
		gain_tempo(tempo_gain)

	return final_damage


func begin_power_attack(ability: AbilityDefinition) -> void:
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
