extends RefCounted
class_name BattleEffectResult

var action: BattleAction
var effect: AbilityEffectDefinition
var source: CombatantState
var target: CombatantState
var timing_result: BattleAction.TimingResult = BattleAction.TimingResult.NONE

var hp_before: int = 0
var hp_after: int = 0
var tempo_before: int = 0
var tempo_after: int = 0
var amount: int = 0

var applied: bool = false
var skipped: bool = false
var missed: bool = false
var defeated: bool = false
var revived: bool = false
var disrupted: bool = false
var guarded: bool = false
var status_applied: bool = false
var statuses_removed: int = 0


func _init(
	source_action: BattleAction,
	source_effect: AbilityEffectDefinition,
	effect_target: CombatantState
) -> void:
	action = source_action
	effect = source_effect
	target = effect_target

	if action != null:
		source = action.actor
		timing_result = action.timing_result

	if target != null:
		hp_before = target.current_hp
		hp_after = target.current_hp
		tempo_before = target.current_tempo
		tempo_after = target.current_tempo
