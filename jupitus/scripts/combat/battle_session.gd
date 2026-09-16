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
signal action_started(action: BattleAction)
signal action_resolved(action: BattleAction)
signal action_cancelled(action: BattleAction)
signal damage_applied(action: BattleAction, target: CombatantState, amount: int)
signal power_attack_started(enemy: CombatantState)
signal power_attack_disrupted(enemy: CombatantState)
signal battle_won()
signal battle_lost()

var phase: Phase = Phase.IDLE

var player_party: Array[CombatantState] = []
var enemies: Array[CombatantState] = []
var pending_actions: Array[BattleAction] = []


func setup(
	player_definitions: Array[CombatantDefinition],
	enemy_definitions: Array[CombatantDefinition]
) -> void:
	player_party.clear()
	enemies.clear()
	pending_actions.clear()

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
	if phase == Phase.VICTORY or phase == Phase.DEFEAT:
		return

	pending_actions.clear()

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
		push_warning("BattleSession: actions can only be queued during command selection")
		return null

	if actor == null or ability == null:
		push_warning("BattleSession: actor and ability are required")
		return null

	if actor.is_defeated():
		return null

	if ability.kind != AbilityDefinition.Kind.GUARD:
		if not actor.can_use_ability(ability):
			push_warning(
				"BattleSession: '%s' does not have enough Tempo for '%s'"
				% [actor.definition.display_name, ability.display_name]
			)
			return null

		if not actor.spend_tempo(ability.tempo_cost):
			return null

	var action := BattleAction.new(actor, ability, target)
	pending_actions.append(action)
	action_queued.emit(action)

	if ability.is_power_attack:
		actor.begin_power_attack(ability)
		power_attack_started.emit(actor)

	return action


func resolve_actions() -> void:
	if phase != Phase.COMMAND_SELECTION:
		return

	_set_phase(Phase.RESOLVING)

	pending_actions.sort_custom(_sort_actions)

	for action in pending_actions:
		resolve_action(action)

		if phase == Phase.VICTORY or phase == Phase.DEFEAT:
			return

	if _all_enemies_defeated():
		_set_phase(Phase.VICTORY)
		battle_won.emit()
	elif _all_players_defeated():
		_set_phase(Phase.DEFEAT)
		battle_lost.emit()
	else:
		_set_phase(Phase.TURN_COMPLETE)


func resolve_action(action: BattleAction) -> void:
	if action == null or action.cancelled:
		return

	if action.actor == null or action.actor.is_defeated():
		return

	# A perfect regular attack may have disrupted this action before it began.
	if (
		action.ability.is_power_attack
		and action.actor.power_attack_disrupted
	):
		action.cancelled = true
		action.actor.finish_power_attack()
		action_cancelled.emit(action)
		return

	action_started.emit(action)

	match action.ability.kind:
		AbilityDefinition.Kind.GUARD:
			action.actor.choose_guard()

		AbilityDefinition.Kind.REGULAR_ATTACK:
			_resolve_attack(action)

		AbilityDefinition.Kind.SKILL:
			_resolve_attack(action)

		AbilityDefinition.Kind.ITEM:
			push_warning("BattleSession: item actions are not implemented yet")

	if action.ability.is_power_attack:
		action.actor.finish_power_attack()

	action_resolved.emit(action)


func _resolve_attack(action: BattleAction) -> void:
	var target := action.target

	if target == null or target.is_defeated():
		return

	var damage_multiplier: float = 1.0

	match action.timing_result:
		BattleAction.TimingResult.MISS:
			damage_multiplier = 0.0
		BattleAction.TimingResult.GOOD:
			damage_multiplier = 1.25
		BattleAction.TimingResult.PERFECT:
			damage_multiplier = 1.5
		BattleAction.TimingResult.NONE:
			damage_multiplier = 1.0

	# A perfect regular attack disrupts the target's prepared power attack.
	if (
		action.ability.kind == AbilityDefinition.Kind.REGULAR_ATTACK
		and action.timing_result == BattleAction.TimingResult.PERFECT
		and action.ability.disrupts_power_attack_on_perfect
	):
		if target.disrupt_power_attack():
			power_attack_disrupted.emit(target)

	var raw_damage: int = int(round(
		float(action.ability.power) * damage_multiplier
	))

	var damage_dealt: int = target.receive_damage(
		raw_damage,
		action.ability.get_tempo_gain_on_damage()
	)

	if (
		action.ability.kind == AbilityDefinition.Kind.REGULAR_ATTACK
		and action.timing_result != BattleAction.TimingResult.MISS
	):
		action.actor.gain_tempo(
			action.ability.get_tempo_gain_on_use()
		)

	damage_applied.emit(action, target, damage_dealt)


func _sort_actions(first: BattleAction, second: BattleAction) -> bool:
	if first.get_priority() != second.get_priority():
		return first.get_priority() > second.get_priority()

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


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_changed.emit(phase)
