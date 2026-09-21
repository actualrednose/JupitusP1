extends RefCounted
class_name BattleAction

enum TimingResult {
	NONE,
	MISS,
	GOOD,
	PERFECT,
}

var actor: CombatantState
var ability: AbilityDefinition
var target: CombatantState

var timing_result: TimingResult = TimingResult.NONE
var timing_completed: bool = false
var timing_success_count: int = 0
var cancelled: bool = false
var effect_results: Array[BattleEffectResult] = []


func _init(
	source_actor: CombatantState,
	source_ability: AbilityDefinition,
	source_target: CombatantState = null
) -> void:
	actor = source_actor
	ability = source_ability
	target = source_target


func get_priority() -> int:
	if ability == null:
		return 0

	return ability.action_priority


func get_speed() -> int:
	if actor == null or actor.definition == null:
		return 0

	return actor.definition.speed
