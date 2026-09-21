extends Node
class_name BattleController

@export_group("Battle Setup")
@export var player_definitions: Array[CombatantDefinition] = []
@export var enemy_definitions: Array[CombatantDefinition] = []
@export var auto_start: bool = true

@export_group("Debug Input")
@export var attack_action: StringName = &"interact"
@export var guard_action: StringName = &"ui_cancel"
@export var resolve_action: StringName = &"ui_accept"
## Shows enemy action text above their sprites when enabled.
@export var debug_show_enemy_intents: bool = false:
	set(value):
		debug_show_enemy_intents = value

		if is_inside_tree():
			_set_enemy_intent_debug_visibility()

@export_group("Battle Actors")
@export var enemy_actors: Array[BattleEnemyActor] = []
## Optional presentation director. One is created automatically when unassigned.
@export var presentation_director: BattlePresentationDirector

signal player_action_changed(action: BattleAction)
signal active_player_changed(player: CombatantState)
signal enemy_intent_changed(intent: EnemyActionIntent)
signal timing_requested(
	action: BattleAction,
	target_position: Vector2
)

var battle_session: BattleSession
var selected_player_action: BattleAction = null
var selected_player_actions: Dictionary = {}
var enemy_intents: Dictionary = {}
var active_player: CombatantState = null
var enemy_actions_queued: bool = false


func _ready() -> void:
	battle_session = BattleSession.new()
	_ensure_presentation_director()

	battle_session.phase_changed.connect(_on_phase_changed)
	battle_session.action_queued.connect(_on_action_queued)
	battle_session.timing_requested.connect(_on_timing_requested)
	battle_session.action_started.connect(_on_action_started)
	battle_session.action_resolved.connect(_on_action_resolved)
	battle_session.action_cancelled.connect(_on_action_cancelled)
	battle_session.damage_applied.connect(_on_damage_applied)
	battle_session.power_attack_started.connect(_on_power_attack_started)
	battle_session.power_attack_disrupted.connect(_on_power_attack_disrupted)
	battle_session.battle_won.connect(_on_battle_won)
	battle_session.battle_lost.connect(_on_battle_lost)

	battle_session.setup(player_definitions, enemy_definitions)
	presentation_director.setup(battle_session)
	_bind_enemy_actors()

	if auto_start:
		battle_session.start_turn()


func _unhandled_input(event: InputEvent) -> void:
	if battle_session == null:
		return

	if battle_session.phase != BattleSession.Phase.COMMAND_SELECTION:
		return

	if event.is_action_pressed(attack_action):
		_select_main_attack()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed(guard_action):
		_select_guard()
		get_viewport().set_input_as_handled()

	elif event.is_action_pressed(resolve_action):
		_resolve_turn()
		get_viewport().set_input_as_handled()


func _select_main_attack() -> void:
	choose_main_attack(_get_first_living_enemy())

func _select_guard() -> void:
	choose_guard()

func _resolve_turn() -> void:
	confirm_turn()

func _queue_enemy_actions() -> void:
	if enemy_actions_queued:
		return

	if battle_session.enemies.is_empty():
		return

	if battle_session.player_party.is_empty():
		return

	for enemy in battle_session.enemies:
		if enemy.is_defeated():
			continue

		var profile := enemy.definition.ai_profile

		if profile == null:
			print(
				"Enemy AI [Round %d]: %s -> No AI profile"
				% [
					battle_session.turn_number,
					enemy.definition.display_name
				]
			)
			continue

		var table_name := profile.get_matching_table_name(
			enemy,
			battle_session
		)

		if table_name == "Base actions":
			table_name = "Base actions (no conditional matched)"

		print(
			"Enemy AI [Round %d]: %s -> %s"
			% [
				battle_session.turn_number,
				enemy.definition.display_name,
				table_name
			]
		)

		var intent := BattleAI.choose_intent(
			enemy,
			profile,
			battle_session
		)

		if intent == null:
			push_warning(
				"BattleController: '%s' could not choose a valid AI action"
				% enemy.definition.display_name
			)
			continue

		var action := battle_session.queue_action(
			enemy,
			intent.ability,
			intent.target
		)

		if action == null:
			continue

		enemy_intents[enemy] = intent
		_set_enemy_actor_intent(enemy, intent)
		enemy_intent_changed.emit(intent)

	enemy_actions_queued = true


func _get_first_living_enemy() -> CombatantState:
	for enemy in battle_session.enemies:
		if not enemy.is_defeated():
			return enemy

	return null


func _get_first_living_player() -> CombatantState:
	for player in battle_session.player_party:
		if not player.is_defeated():
			return player

	return null


func _on_phase_changed(new_phase: BattleSession.Phase) -> void:
	print("Battle phase: %s" % BattleSession.Phase.keys()[new_phase])

	if new_phase == BattleSession.Phase.COMMAND_SELECTION:
		selected_player_action = null
		selected_player_actions.clear()
		enemy_intents.clear()
		_clear_enemy_actor_intents()
		enemy_actions_queued = false
		_queue_enemy_actions()
		_advance_active_player()

	elif new_phase == BattleSession.Phase.TURN_COMPLETE:
		call_deferred("_start_next_turn")


func _on_action_queued(action: BattleAction) -> void:
	print(
		"Action queued: %s uses %s"
		% [
			action.actor.definition.display_name,
			action.ability.display_name
		]
	)


func _on_action_started(action: BattleAction) -> void:
	print(
		"Action started: %s uses %s"
		% [
			action.actor.definition.display_name,
			action.ability.display_name
		]
	)

	if action.actor.team == CombatantState.Team.ENEMY:
		enemy_intents.erase(action.actor)
		_set_enemy_actor_intent(action.actor, null)


func _on_action_resolved(action: BattleAction) -> void:
	print(
		"Action resolved: %s"
		% action.ability.display_name
	)


func _on_action_cancelled(action: BattleAction) -> void:
	print(
		"Action cancelled: %s's %s was disrupted"
		% [
			action.actor.definition.display_name,
			action.ability.display_name
		]
	)

	if action.actor.team == CombatantState.Team.ENEMY:
		enemy_intents.erase(action.actor)
		_set_enemy_actor_intent(action.actor, null)


func _on_damage_applied(
	action: BattleAction,
	target: CombatantState,
	amount: int
) -> void:
	print(
		"%s took %d damage. HP: %d/%d, Tempo: %d/%d"
		% [
			target.definition.display_name,
			amount,
			target.current_hp,
			target.definition.max_hp,
			target.current_tempo,
			target.definition.max_tempo
		]
	)


func _on_power_attack_started(enemy: CombatantState) -> void:
	print(
		"SKULL: %s is preparing a power attack!"
		% enemy.definition.display_name
	)

	_sync_enemy_actors()
	presentation_director.present_power_attack_charge(enemy)


func _on_power_attack_disrupted(enemy: CombatantState) -> void:
	print(
		"POWER ATTACK DISRUPTED: %s"
		% enemy.definition.display_name
	)

func _on_battle_won() -> void:
	_clear_enemy_actor_intents()
	print("BATTLE WON")


func _on_battle_lost() -> void:
	_clear_enemy_actor_intents()
	print("BATTLE LOST")
	
func start_battle() -> void:
	if battle_session == null:
		push_warning("BattleController: battle session has not been created")
		return

	if battle_session.phase == BattleSession.Phase.IDLE:
		battle_session.start_turn()


func choose_main_attack(target: CombatantState) -> void:
	if target == null or target.is_defeated():
		return

	var player := get_current_player()

	if player == null:
		return

	if player.definition.main_attack == null:
		push_warning(
			"BattleController: '%s' has no main attack"
			% player.definition.display_name
		)
		return

	var action := battle_session.queue_action(
		player,
		player.definition.main_attack,
		target
	)

	if action == null:
		return

	_record_player_action(player, action)


func choose_guard() -> void:
	var player := get_current_player()

	if player == null:
		return

	if player.definition.guard_ability == null:
		push_warning(
			"BattleController: '%s' has no guard ability"
			% player.definition.display_name
		)
		return

	var action := battle_session.queue_action(
		player,
		player.definition.guard_ability
	)

	if action == null:
		return

	_record_player_action(player, action)


func choose_skill(
	ability: AbilityDefinition,
	target: CombatantState = null
) -> void:
	var player := get_current_player()

	if player == null or ability == null:
		return

	if not player.definition.skills.has(ability):
		push_warning(
			"BattleController: '%s' does not know '%s'"
			% [
				player.definition.display_name,
				ability.display_name
			]
		)
		return

	var action := battle_session.queue_action(
		player,
		ability,
		target
	)

	if action == null:
		return

	_record_player_action(player, action)


func get_current_player() -> CombatantState:
	if active_player == null or active_player.is_defeated():
		return null

	return active_player


func all_player_actions_selected() -> bool:
	var living_player_found := false

	for player in battle_session.player_party:
		if player.is_defeated():
			continue

		living_player_found = true

		if not selected_player_actions.has(player):
			return false

	return living_player_found


func confirm_turn() -> void:
	if not all_player_actions_selected():
		return

	selected_player_action = null
	battle_session.resolve_actions()


func reselect_player(player: CombatantState) -> bool:
	if (
		battle_session == null
		or battle_session.phase
			!= BattleSession.Phase.COMMAND_SELECTION
		or player == null
		or player.is_defeated()
		or not battle_session.player_party.has(player)
		or not selected_player_actions.has(player)
	):
		return false

	var removed_action := (
		battle_session.remove_queued_action(player)
	)

	if removed_action == null:
		return false

	selected_player_actions.erase(player)
	selected_player_action = null
	active_player = player

	player_action_changed.emit(null)
	active_player_changed.emit(active_player)
	return true


func return_to_previous_player() -> bool:
	if (
		battle_session == null
		or battle_session.phase
			!= BattleSession.Phase.COMMAND_SELECTION
	):
		return false

	var start_index := (
		battle_session.player_party.size() - 1
	)

	if active_player != null:
		start_index = (
			battle_session.player_party.find(
				active_player
			) - 1
		)

	for index in range(start_index, -1, -1):
		var player := (
			battle_session.player_party[index]
		)

		if selected_player_actions.has(player):
			return reselect_player(player)

	return false


func skip_action_presentation() -> void:
	if battle_session == null:
		return

	if (
		presentation_director != null
		and presentation_director.is_presenting()
	):
		presentation_director.skip_current_presentation()
	else:
		battle_session.continue_resolution()


func set_presentation_fast_forwarding(value: bool) -> void:
	if presentation_director != null:
		presentation_director.set_fast_forwarding(value)


func submit_timing_result(
	action: BattleAction,
	timing_result: BattleAction.TimingResult,
	timing_success_count: int = 0
) -> bool:
	if battle_session == null:
		return false

	return battle_session.submit_timing_result(
		action,
		timing_result,
		timing_success_count
	)


func _record_player_action(
	player: CombatantState,
	action: BattleAction
) -> void:
	selected_player_action = action
	selected_player_actions[player] = action
	player_action_changed.emit(action)
	_advance_active_player()

	if all_player_actions_selected():
		call_deferred("_confirm_if_ready")


func _advance_active_player() -> void:
	var next_player: CombatantState = null

	for player in battle_session.player_party:
		if (
			not player.is_defeated()
			and not selected_player_actions.has(player)
		):
			next_player = player
			break

	active_player = next_player
	active_player_changed.emit(active_player)


func _start_next_turn() -> void:
	if battle_session.phase == BattleSession.Phase.TURN_COMPLETE:
		battle_session.start_turn()


func _confirm_if_ready() -> void:
	if (
		battle_session.phase
			== BattleSession.Phase.COMMAND_SELECTION
		and all_player_actions_selected()
	):
		confirm_turn()


func _on_timing_requested(
	action: BattleAction
) -> void:
	if (
		action == null
		or action.target == null
	):
		push_error(
			"BattleController: timed action has no target"
		)
		battle_session.submit_timing_result(
			action,
			BattleAction.TimingResult.NONE
		)
		return

	var target_actor := _find_enemy_actor(
		action.target
	)

	if target_actor == null:
		push_error(
			"BattleController: no enemy actor is bound to timing target '%s'"
			% action.target.definition.display_name
		)
		battle_session.submit_timing_result(
			action,
			BattleAction.TimingResult.NONE
		)
		return

	timing_requested.emit(
		action,
		target_actor.get_timing_target_position()
	)


func _find_enemy_actor(
	enemy: CombatantState
) -> BattleEnemyActor:
	for actor in enemy_actors:
		if (
			actor != null
			and actor.combatant == enemy
		):
			return actor

	return null


func _bind_enemy_actors() -> void:
	var count: int = mini(
		enemy_actors.size(),
		battle_session.enemies.size()
	)

	for i in range(count):
		enemy_actors[i].bind_combatant(
			battle_session.enemies[i]
		)
		presentation_director.register_view(
			battle_session.enemies[i],
			enemy_actors[i]
		)
		enemy_actors[i].set_debug_intent_visible(
			debug_show_enemy_intents
		)

	if enemy_actors.size() != battle_session.enemies.size():
		push_warning(
			"BattleController: enemy actor count does not match enemy combatant count"
		)


func _sync_enemy_actors() -> void:
	for actor in enemy_actors:
		if actor:
			actor.sync_from_state()


func _set_enemy_actor_intent(
	enemy: CombatantState,
	intent: EnemyActionIntent
) -> void:
	for actor in enemy_actors:
		if actor != null and actor.combatant == enemy:
			actor.set_intent(intent)
			return


func _clear_enemy_actor_intents() -> void:
	for actor in enemy_actors:
		if actor != null:
			actor.set_intent(null)


func _set_enemy_intent_debug_visibility() -> void:
	for actor in enemy_actors:
		if actor != null:
			actor.set_debug_intent_visible(
				debug_show_enemy_intents
			)


func _ensure_presentation_director() -> void:
	if presentation_director != null:
		return

	presentation_director = BattlePresentationDirector.new()
	presentation_director.name = "BattlePresentationDirector"
	add_child(presentation_director)
