extends RefCounted
class_name BattleSession

enum Phase {
	IDLE,
	COMMAND_SELECTION,
	RESOLVING,
	TURN_COMPLETE,
	VICTORY,
	DEFEAT,
}

signal phase_changed(new_phase: Phase)
signal action_queued(action: BattleAction)
signal timing_requested(action: BattleAction)
signal action_started(action: BattleAction)
signal action_resolved(action: BattleAction)
signal action_cancelled(action: BattleAction)
signal effect_resolved(result: BattleEffectResult)
signal damage_applied(
	action: BattleAction,
	target: CombatantState,
	amount: int
)
signal healing_applied(
	action: BattleAction,
	target: CombatantState,
	amount: int
)
signal power_attack_started(enemy: CombatantState)
signal power_attack_disrupted(enemy: CombatantState)
signal battle_won()
signal battle_lost()

var phase: Phase = Phase.IDLE

var player_party: Array[CombatantState] = []
var enemies: Array[CombatantState] = []
var pending_actions: Array[BattleAction] = []
var turn_number: int = 0
var rng := RandomNumberGenerator.new()

var _resolution_index: int = 0
var _awaiting_action_advance: bool = false
var _awaiting_timing_action: BattleAction = null


func _init() -> void:
	rng.randomize()


func setup(
	player_definitions: Array[CombatantDefinition],
	enemy_definitions: Array[CombatantDefinition]
) -> void:
	player_party.clear()
	enemies.clear()
	pending_actions.clear()

	turn_number = 0
	_resolution_index = 0
	_awaiting_action_advance = false
	_awaiting_timing_action = null

	for definition in player_definitions:
		if definition == null:
			continue

		player_party.append(
			CombatantState.new(
				definition,
				CombatantState.Team.PLAYER
			)
		)

	for definition in enemy_definitions:
		if definition == null:
			continue

		enemies.append(
			CombatantState.new(
				definition,
				CombatantState.Team.ENEMY
			)
		)

	_set_phase(Phase.IDLE)


func start_turn() -> void:
	if (
		phase == Phase.VICTORY
		or phase == Phase.DEFEAT
	):
		return

	pending_actions.clear()
	turn_number += 1
	_resolution_index = 0
	_awaiting_action_advance = false
	_awaiting_timing_action = null

	for combatant in _all_combatants():
		if not combatant.is_defeated():
			combatant.begin_turn()

	_set_phase(Phase.COMMAND_SELECTION)


func queue_action(
	actor: CombatantState,
	ability: AbilityDefinition,
	target: CombatantState = null
) -> BattleAction:
	if phase != Phase.COMMAND_SELECTION:
		push_warning(
			"BattleSession: actions can only be queued during command selection"
		)
		return null

	if actor == null or ability == null:
		push_warning(
			"BattleSession: actor and ability are required"
		)
		return null

	if actor.is_defeated():
		return null

	if has_queued_action(actor):
		push_warning(
			"BattleSession: '%s' already has a queued action"
			% actor.definition.display_name
		)
		return null

	if ability.effects.is_empty():
		push_warning(
			"BattleSession: '%s' has no effects"
			% ability.display_name
		)
		return null

	var has_valid_target := false

	var target_probe := BattleAction.new(
		actor,
		ability,
		target
	)

	for effect in ability.effects:
		if (
			effect != null
			and not _resolve_effect_targets(
				target_probe,
				effect
			).is_empty()
		):
			has_valid_target = true
			break

	if not has_valid_target:
		push_warning(
			"BattleSession: '%s' has no valid targets"
			% ability.display_name
		)
		return null

	if ability.kind != AbilityDefinition.Kind.GUARD:
		if not actor.can_use_ability(ability):
			push_warning(
				"BattleSession: '%s' does not have enough Tempo for '%s'"
				% [
					actor.definition.display_name,
					ability.display_name
				]
			)
			return null

		if not actor.spend_tempo(
			ability.tempo_cost
		):
			return null

	var action := BattleAction.new(
		actor,
		ability,
		target
	)

	pending_actions.append(action)
	action_queued.emit(action)

	if ability.is_power_attack:
		actor.begin_power_attack(ability)
		power_attack_started.emit(actor)

	return action


func has_queued_action(
	actor: CombatantState
) -> bool:
	for action in pending_actions:
		if (
			action != null
			and action.actor == actor
		):
			return true

	return false


func remove_queued_action(
	actor: CombatantState
) -> BattleAction:
	if (
		phase != Phase.COMMAND_SELECTION
		or actor == null
	):
		return null

	for index in range(
		pending_actions.size()
	):
		var action := pending_actions[index]

		if (
			action == null
			or action.actor != actor
		):
			continue

		pending_actions.remove_at(index)

		if (
			action.ability != null
			and action.ability.kind
				!= AbilityDefinition.Kind.GUARD
			and action.ability.tempo_cost > 0
		):
			actor.change_tempo(
				action.ability.tempo_cost
			)

		if (
			action.ability != null
			and action.ability.is_power_attack
		):
			actor.finish_power_attack()

		return action

	return null


func resolve_actions() -> void:
	if phase != Phase.COMMAND_SELECTION:
		return

	pending_actions.sort_custom(_sort_actions)

	_resolution_index = 0
	_awaiting_action_advance = false
	_awaiting_timing_action = null

	_set_phase(Phase.RESOLVING)
	_resolve_next_action()


func continue_resolution() -> void:
	if (
		phase != Phase.RESOLVING
		or not _awaiting_action_advance
	):
		return

	_awaiting_action_advance = false

	if _finish_battle_if_needed():
		return

	_resolve_next_action()


func is_waiting_for_action_advance() -> bool:
	return _awaiting_action_advance


func is_waiting_for_timing() -> bool:
	return _awaiting_timing_action != null


func submit_timing_result(
	action: BattleAction,
	timing_result: BattleAction.TimingResult
) -> bool:
	if (
		phase != Phase.RESOLVING
		or action == null
		or action != _awaiting_timing_action
	):
		return false

	if (
		timing_result
			< BattleAction.TimingResult.NONE
		or timing_result
			> BattleAction.TimingResult.PERFECT
	):
		push_error(
			"BattleSession: invalid timing result %d"
			% timing_result
		)
		return false

	action.timing_result = timing_result
	action.timing_completed = true
	_awaiting_timing_action = null

	call_deferred("_resolve_next_action")

	return true


func set_random_seed(value: int) -> void:
	rng.seed = value


func _resolve_next_action() -> void:
	if _awaiting_timing_action != null:
		return

	while _resolution_index < pending_actions.size():
		var action := pending_actions[
			_resolution_index
		]

		if _requires_player_timing(action):
			_awaiting_timing_action = action
			timing_requested.emit(action)
			return

		_resolution_index += 1

		if resolve_action(action):
			_awaiting_action_advance = true
			return

	_finish_resolution()


func _requires_player_timing(
	action: BattleAction
) -> bool:
	return (
		action != null
		and not action.cancelled
		and action.actor != null
		and not action.actor.is_defeated()
		and action.actor.team
			== CombatantState.Team.PLAYER
		and action.target != null
		and not action.target.is_defeated()
		and action.ability != null
		and action.ability.timing_type
			!= AbilityDefinition.TimingType.NONE
		and not action.timing_completed
	)


func resolve_action(
	action: BattleAction
) -> bool:
	if action == null or action.cancelled:
		return false

	if (
		action.actor == null
		or action.actor.is_defeated()
	):
		return false

	# A perfect regular attack may have disrupted this
	# action before it began.
	if (
		action.ability.is_power_attack
		and action.actor.power_attack_disrupted
	):
		action.cancelled = true
		action.actor.finish_power_attack()
		action_cancelled.emit(action)
		return false

	action_started.emit(action)
	action.effect_results.clear()

	if action.ability.effects.is_empty():
		push_warning(
			"BattleSession: '%s' has no effects"
			% action.ability.display_name
		)
	else:
		_resolve_effects(action)

	if action.ability.is_power_attack:
		action.actor.finish_power_attack()

	action_resolved.emit(action)

	return true


func _resolve_effects(
	action: BattleAction
) -> void:
	for effect in action.ability.effects:
		if effect == null:
			push_warning(
				"BattleSession: '%s' contains an empty effect"
				% action.ability.display_name
			)
			continue

		var targets := _resolve_effect_targets(
			action,
			effect
		)

		if targets.is_empty():
			var skipped_result := (
				BattleEffectResult.new(
					action,
					effect,
					action.target
				)
			)

			skipped_result.skipped = true

			action.effect_results.append(
				skipped_result
			)

			effect_resolved.emit(
				skipped_result
			)

			continue

		for target in targets:
			var result := _apply_effect(
				action,
				effect,
				target
			)

			action.effect_results.append(result)
			effect_resolved.emit(result)


func _resolve_effect_targets(
	action: BattleAction,
	effect: AbilityEffectDefinition
) -> Array[CombatantState]:
	var targets: Array[CombatantState] = []

	match effect.target_type:
		AbilityEffectDefinition.TargetType.SELECTED_ENEMY:
			if (
				action.target != null
				and action.target.team
					!= action.actor.team
				and _can_receive_effect(
					action.target,
					effect
				)
			):
				targets.append(action.target)

		AbilityEffectDefinition.TargetType.SELECTED_ALLY:
			if (
				action.target != null
				and action.target.team
					== action.actor.team
				and _can_receive_effect(
					action.target,
					effect
				)
			):
				targets.append(action.target)

		AbilityEffectDefinition.TargetType.SELF:
			if _can_receive_effect(
				action.actor,
				effect
			):
				targets.append(action.actor)

		AbilityEffectDefinition.TargetType.ALL_ALLIES:
			for target in _get_allies(
				action.actor
			):
				if _can_receive_effect(
					target,
					effect
				):
					targets.append(target)

		AbilityEffectDefinition.TargetType.ALL_ENEMIES:
			for target in _get_opponents(
				action.actor
			):
				if _can_receive_effect(
					target,
					effect
				):
					targets.append(target)

	return targets


func _can_receive_effect(
	target: CombatantState,
	effect: AbilityEffectDefinition
) -> bool:
	if target == null:
		return false

	if (
		effect.effect_type
		== AbilityEffectDefinition.EffectType.REVIVE
	):
		return target.is_defeated()

	return not target.is_defeated()


func _apply_effect(
	action: BattleAction,
	effect: AbilityEffectDefinition,
	target: CombatantState
) -> BattleEffectResult:
	var result := BattleEffectResult.new(
		action,
		effect,
		target
	)

	if not effect.meets_timing_requirement(
		action.timing_result
	):
		result.skipped = true

		result.missed = (
			action.timing_result
			== BattleAction.TimingResult.MISS
		)

		return result

	if (
		effect.application_chance < 1.0
		and rng.randf()
			>= effect.application_chance
	):
		result.skipped = true
		return result

	var value := effect.roll_value(rng)

	match effect.effect_type:
		AbilityEffectDefinition.EffectType.DAMAGE:
			result.missed = (
				action.timing_result
				== BattleAction.TimingResult.MISS
			)

			if effect.scales_with_timing:
				value = int(
					round(
						float(value)
						* _get_timing_multiplier(
							action.timing_result
						)
					)
				)

			result.amount = target.receive_damage(
				value,
				effect.roll_target_tempo_gain(rng)
			)

			result.applied = result.amount > 0

			damage_applied.emit(
				action,
				target,
				result.amount
			)

		AbilityEffectDefinition.EffectType.HEAL:
			result.amount = (
				target.receive_healing(value)
			)

			result.applied = result.amount > 0

			healing_applied.emit(
				action,
				target,
				result.amount
			)

		AbilityEffectDefinition.EffectType.TEMPO:
			result.amount = target.change_tempo(
				value
			)

			result.applied = result.amount != 0

		AbilityEffectDefinition.EffectType.GUARD:
			target.choose_guard()
			result.guarded = true
			result.applied = true

		AbilityEffectDefinition.EffectType.APPLY_STATUS:
			result.status_applied = (
				target.apply_status(
					effect.status,
					effect.status_duration_override
				)
			)

			result.applied = result.status_applied

		AbilityEffectDefinition.EffectType.CLEANSE:
			result.statuses_removed = (
				target.cleanse_statuses(
					effect.status
				)
			)

			result.amount = (
				result.statuses_removed
			)

			result.applied = (
				result.statuses_removed > 0
			)

		AbilityEffectDefinition.EffectType.REVIVE:
			result.amount = target.revive(
				value
			)

			result.revived = result.amount > 0
			result.applied = result.revived

		AbilityEffectDefinition.EffectType.STAGGER:
			if value > 0:
				result.disrupted = (
					target.disrupt_power_attack()
				)

				result.applied = result.disrupted

				if result.disrupted:
					power_attack_disrupted.emit(
						target
					)

	result.hp_after = target.current_hp
	result.tempo_after = target.current_tempo

	result.defeated = (
		result.hp_before > 0
		and target.is_defeated()
	)

	return result


func _get_timing_multiplier(
	timing_result: BattleAction.TimingResult
) -> float:
	match timing_result:
		BattleAction.TimingResult.MISS:
			return 0.0

		BattleAction.TimingResult.GOOD:
			return 1.25

		BattleAction.TimingResult.PERFECT:
			return 1.5

		BattleAction.TimingResult.NONE:
			return 1.0

	return 1.0


func _get_allies(
	actor: CombatantState
) -> Array[CombatantState]:
	if actor.team == CombatantState.Team.PLAYER:
		return player_party

	return enemies


func _get_opponents(
	actor: CombatantState
) -> Array[CombatantState]:
	if actor.team == CombatantState.Team.PLAYER:
		return enemies

	return player_party


func _finish_resolution() -> void:
	if _finish_battle_if_needed():
		return

	_set_phase(Phase.TURN_COMPLETE)


func _finish_battle_if_needed() -> bool:
	if _all_enemies_defeated():
		_set_phase(Phase.VICTORY)
		battle_won.emit()
		return true

	if _all_players_defeated():
		_set_phase(Phase.DEFEAT)
		battle_lost.emit()
		return true

	return false


func _sort_actions(
	first: BattleAction,
	second: BattleAction
) -> bool:
	if first.get_priority() != second.get_priority():
		return (
			first.get_priority()
			> second.get_priority()
		)

	return first.get_speed() > second.get_speed()


func _all_combatants() -> Array[CombatantState]:
	var result: Array[CombatantState] = []

	result.append_array(player_party)
	result.append_array(enemies)

	return result


func _all_enemies_defeated() -> bool:
	if enemies.is_empty():
		return false

	for enemy in enemies:
		if not enemy.is_defeated():
			return false

	return true


func _all_players_defeated() -> bool:
	if player_party.is_empty():
		return true

	for player in player_party:
		if not player.is_defeated():
			return false

	return true


func _set_phase(
	new_phase: Phase
) -> void:
	phase = new_phase
	phase_changed.emit(phase)
