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
@export_group("Battle Actors")
@export var enemy_actors: Array[BattleEnemyActor] = []
## Temporary result used until the timing minigame exists.
## 3 = PERFECT, 2 = GOOD, 1 = MISS, 0 = NONE.
@export_range(0, 3) var debug_timing_result: int = BattleAction.TimingResult.PERFECT
signal player_action_changed(action: BattleAction)

var battle_session: BattleSession
var selected_player_action: BattleAction = null
var enemy_action_queued: bool = false


func _ready() -> void:
	battle_session = BattleSession.new()

	battle_session.phase_changed.connect(_on_phase_changed)
	battle_session.action_queued.connect(_on_action_queued)
	battle_session.action_started.connect(_on_action_started)
	battle_session.action_resolved.connect(_on_action_resolved)
	battle_session.action_cancelled.connect(_on_action_cancelled)
	battle_session.damage_applied.connect(_on_damage_applied)
	battle_session.power_attack_started.connect(_on_power_attack_started)
	battle_session.power_attack_disrupted.connect(_on_power_attack_disrupted)
	battle_session.battle_won.connect(_on_battle_won)
	battle_session.battle_lost.connect(_on_battle_lost)

	battle_session.setup(player_definitions, enemy_definitions)
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

func _queue_enemy_action() -> void:
	if enemy_action_queued:
		return

	if battle_session.enemies.is_empty():
		return

	if battle_session.player_party.is_empty():
		return

	var enemy: CombatantState = battle_session.enemies[0]
	var target: CombatantState = _get_first_living_player()

	if enemy.is_defeated() or target == null:
		return

	var ability: AbilityDefinition = enemy.definition.main_attack

	# For testing, prefer the enemy's power attack when one is configured.
	if enemy.definition.power_attack != null:
		ability = enemy.definition.power_attack

	if ability == null:
		push_warning(
			"BattleController: '%s' has no attack ability"
			% enemy.definition.display_name
		)
		return

	var action := battle_session.queue_action(enemy, ability, target)

	if action != null:
		enemy_action_queued = true


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
		enemy_action_queued = false
		_queue_enemy_action()

	elif new_phase == BattleSession.Phase.TURN_COMPLETE:
		battle_session.start_turn()


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

	_sync_enemy_actors()


func _on_power_attack_started(enemy: CombatantState) -> void:
	print(
		"SKULL: %s is preparing a power attack!"
		% enemy.definition.display_name
	)

	_sync_enemy_actors()


func _on_power_attack_disrupted(enemy: CombatantState) -> void:
	print(
		"POWER ATTACK DISRUPTED: %s"
		% enemy.definition.display_name
	)

	_sync_enemy_actors()

func _on_battle_won() -> void:
	print("BATTLE WON")


func _on_battle_lost() -> void:
	print("BATTLE LOST")
	
func start_battle() -> void:
	if battle_session == null:
		push_warning("BattleController: battle session has not been created")
		return

	if battle_session.phase == BattleSession.Phase.IDLE:
		battle_session.start_turn()


func choose_main_attack(target: CombatantState) -> void:
	if selected_player_action != null:
		return

	if target == null or target.is_defeated():
		return

	if battle_session.player_party.is_empty():
		return

	var player: CombatantState = battle_session.player_party[0]

	if player.definition.main_attack == null:
		push_warning(
			"BattleController: '%s' has no main attack"
			% player.definition.display_name
		)
		return

	selected_player_action = battle_session.queue_action(
		player,
		player.definition.main_attack,
		target
	)

	if selected_player_action == null:
		return

	# Temporary until the timing minigame is added.
	selected_player_action.timing_result = debug_timing_result

	player_action_changed.emit(selected_player_action)


func choose_guard() -> void:
	if selected_player_action != null:
		return

	if battle_session.player_party.is_empty():
		return

	var player: CombatantState = battle_session.player_party[0]

	if player.definition.guard_ability == null:
		push_warning(
			"BattleController: '%s' has no guard ability"
			% player.definition.display_name
		)
		return

	selected_player_action = battle_session.queue_action(
		player,
		player.definition.guard_ability
	)

	if selected_player_action == null:
		return

	player_action_changed.emit(selected_player_action)


func confirm_turn() -> void:
	if selected_player_action == null:
		return

	selected_player_action = null
	battle_session.resolve_actions()
	
func _bind_enemy_actors() -> void:
	var count: int = mini(
		enemy_actors.size(),
		battle_session.enemies.size()
	)

	for i in range(count):
		enemy_actors[i].bind_combatant(
			battle_session.enemies[i]
		)

	if enemy_actors.size() != battle_session.enemies.size():
		push_warning(
			"BattleController: enemy actor count does not match enemy combatant count"
		)


func _sync_enemy_actors() -> void:
	for actor in enemy_actors:
		if actor:
			actor.sync_from_state()
