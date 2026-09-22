extends CanvasLayer
class_name BattleHUD

@export var battle_controller: BattleController

@export_group("Emm Crosshair Timing")
## Assign Emm's crosshair image here after importing it.
## A simple temporary crosshair is drawn when this is empty.
@export var emm_crosshair_texture: Texture2D
## Horizontal travel speed in screen pixels per second.
@export_range(100.0, 1600.0, 10.0) var emm_crosshair_speed: float = 500.0
## Maximum horizontal distance from the head for a Killshot.
@export_range(1.0, 100.0, 1.0) var emm_killshot_radius: float = 24.0
## Maximum horizontal distance from the head for a Clean shot.
@export_range(1.0, 240.0, 1.0) var emm_clean_shot_radius: float = 72.0

@export_group("Roommate Direction Timing")
## Seconds allowed to enter the ability's full direction sequence.
@export_range(0.5, 10.0, 0.05) var roommate_input_time: float = 2.25
## Played for every correct direction. Leave empty to disable.
@export var roommate_punch_sound: AudioStream

@onready var party_list: HBoxContainer = (
	$Root/ScreenMargin/Layout/PartyList
)

@onready var attack_button: Button = (
	$Root/ScreenMargin/Layout/CommandBar/AttackButton
)

@onready var skill_button: Button = (
	$Root/ScreenMargin/Layout/CommandBar/SkillButton
)

@onready var guard_button: Button = (
	$Root/ScreenMargin/Layout/CommandBar/GuardButton
)

@onready var confirm_button: Button = (
	$Root/ScreenMargin/Layout/CommandBar/ConfirmButton
)

@onready var status_label: Label = (
	$Root/ScreenMargin/Layout/StatusLabel
)

var _refresh_pending: bool = false
var selecting_attack_target: bool = false
var selecting_ally_target: bool = false
var _pending_target_ability: AbilityDefinition
var _party_cards: Dictionary = {}
var _presentation_director: BattlePresentationDirector
var _skill_menu: HBoxContainer
var _skill_menu_open: bool = false
var _crosshair_minigame: CrosshairTimingMinigame
var _direction_minigame: DirectionTimingMinigame
var _keyboard_enemy: BattleEnemyActor
var _keyboard_ally: CombatantState


func _ready() -> void:
	if battle_controller == null:
		push_error(
			"BattleHUD: assign a BattleController in the Inspector"
		)
		return

	attack_button.pressed.connect(_on_attack_pressed)
	skill_button.pressed.connect(_on_skill_pressed)
	guard_button.pressed.connect(_on_guard_pressed)
	confirm_button.visible = false
	_create_skill_menu()
	_create_crosshair_minigame()
	_create_direction_minigame()

	call_deferred("_connect_to_battle")


func _connect_to_battle() -> void:
	if (
		battle_controller == null
		or battle_controller.battle_session == null
	):
		push_error(
			"BattleHUD: BattleController has no BattleSession"
		)
		return

	var session: BattleSession = (
		battle_controller.battle_session
	)

	if not session.phase_changed.is_connected(
		_on_phase_changed
	):
		session.phase_changed.connect(_on_phase_changed)

	if not session.action_queued.is_connected(
		_on_action_queued
	):
		session.action_queued.connect(_on_action_queued)

	if not session.action_started.is_connected(
		_on_action_started
	):
		session.action_started.connect(_on_action_started)

	if not session.action_cancelled.is_connected(
		_on_action_cancelled
	):
		session.action_cancelled.connect(
			_on_action_cancelled
		)

	if not session.power_attack_started.is_connected(
		_on_power_attack_started
	):
		session.power_attack_started.connect(
			_on_power_attack_started
		)

	if not session.battle_won.is_connected(
		_on_battle_won
	):
		session.battle_won.connect(_on_battle_won)

	if not session.battle_lost.is_connected(
		_on_battle_lost
	):
		session.battle_lost.connect(_on_battle_lost)

	if not battle_controller.player_action_changed.is_connected(
		_on_player_action_changed
	):
		battle_controller.player_action_changed.connect(
			_on_player_action_changed
		)

	if not battle_controller.active_player_changed.is_connected(
		_on_active_player_changed
	):
		battle_controller.active_player_changed.connect(
			_on_active_player_changed
		)

	if not battle_controller.timing_requested.is_connected(
		_on_timing_requested
	):
		battle_controller.timing_requested.connect(
			_on_timing_requested
		)

	_presentation_director = (
		battle_controller.presentation_director
	)

	if _presentation_director != null:
		if not _presentation_director.effect_presentation_started.is_connected(
			_on_effect_presentation_started
		):
			_presentation_director.effect_presentation_started.connect(
				_on_effect_presentation_started
			)

		if not _presentation_director.action_presentation_finished.is_connected(
			_on_action_presentation_finished
		):
			_presentation_director.action_presentation_finished.connect(
				_on_action_presentation_finished
			)

	for actor in battle_controller.enemy_actors:
		if actor == null:
			continue

		if not actor.clicked.is_connected(
			_on_enemy_actor_clicked
		):
			actor.clicked.connect(
				_on_enemy_actor_clicked
			)

	_refresh()
	battle_controller.start_battle()


func _process(_delta: float) -> void:
	if battle_controller == null:
		return

	if _is_timing_minigame_active():
		battle_controller.set_presentation_fast_forwarding(
			false
		)
		return

	var fast_forwarding := (
		Input.is_action_pressed("interact")
		or Input.is_action_pressed("ui_accept")
	)
	battle_controller.set_presentation_fast_forwarding(
		fast_forwarding
	)


func _input(event: InputEvent) -> void:
	if battle_controller == null:
		return

	if battle_controller.battle_session == null:
		return

	if _is_timing_minigame_active():
		if (
			_direction_minigame != null
			and _direction_minigame.is_active()
			and _direction_minigame.handle_input(event)
		):
			get_viewport().set_input_as_handled()
			return

		if _crosshair_minigame.handle_input(event):
			get_viewport().set_input_as_handled()

		return

	var phase := battle_controller.battle_session.phase

	if phase == BattleSession.Phase.COMMAND_SELECTION:
		var navigation_direction := (
			_get_navigation_direction(event)
		)

		if navigation_direction != 0:
			_move_keyboard_selection(
				navigation_direction
			)
			get_viewport().set_input_as_handled()
			return

		if _is_confirm_event(event):
			_activate_keyboard_selection()
			get_viewport().set_input_as_handled()
			return

		if event is InputEventMouseButton:
			var mouse_event := (
				event as InputEventMouseButton
			)

			if (
				mouse_event.button_index
					== MOUSE_BUTTON_RIGHT
				and mouse_event.pressed
			):
				_go_back()
				get_viewport().set_input_as_handled()

		return

	if phase != BattleSession.Phase.RESOLVING:
		return

	var should_skip := event.is_action_pressed("ui_cancel")

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		):
			should_skip = true

	if not should_skip:
		return

	battle_controller.skip_action_presentation()

	get_viewport().set_input_as_handled()


func _on_attack_pressed() -> void:
	if not _is_command_selection_active():
		return

	var player := battle_controller.get_current_player()

	if player == null:
		return

	selecting_attack_target = true
	selecting_ally_target = false
	_pending_target_ability = null
	_hide_skill_menu()
	_set_enemy_target_selection_enabled(true)
	_select_first_keyboard_enemy()

	status_label.text = (
		"%s: choose an enemy target."
		% player.definition.display_name
	)

	_refresh()


func _on_skill_pressed() -> void:
	if not _is_command_selection_active():
		return

	var player := battle_controller.get_current_player()

	if player == null or player.definition.skills.is_empty():
		return

	_cancel_target_selection()
	_show_skill_menu(player)


func _on_guard_pressed() -> void:
	if not _is_command_selection_active():
		return

	_cancel_target_selection()
	_hide_skill_menu()
	battle_controller.choose_guard()
	_refresh()


func _refresh() -> void:
	if _refresh_pending:
		return

	_refresh_pending = true
	call_deferred("_refresh_now")


func _refresh_now() -> void:
	_refresh_pending = false

	if (
		battle_controller == null
		or battle_controller.battle_session == null
	):
		return

	_refresh_party()
	_refresh_commands()


func _refresh_party() -> void:
	var active_player := battle_controller.get_current_player()

	for player in battle_controller.battle_session.player_party:
		var card := _party_cards.get(player) as BattlePartyCard

		if card == null:
			card = BattlePartyCard.new()
			party_list.add_child(card)
			card.bind_combatant(player)
			card.clicked.connect(
				_on_party_card_clicked
			)
			_party_cards[player] = card

			if _presentation_director != null:
				_presentation_director.register_view(
					player,
					card
				)

		card.set_active(player == active_player)
		card.set_keyboard_selected(
			player == _keyboard_ally
		)
		card.set_selected_action(
			battle_controller.selected_player_actions.get(
				player
			) as BattleAction
		)
		card.sync_from_state()


func _refresh_commands() -> void:
	var command_active := _is_command_selection_active()
	var player := battle_controller.get_current_player()

	var can_choose_action := (
		command_active
		and player != null
	)

	attack_button.visible = not _skill_menu_open
	attack_button.disabled = (
		not can_choose_action
		or selecting_attack_target
	)

	guard_button.visible = not _skill_menu_open
	guard_button.disabled = not can_choose_action

	if skill_button != null:
		var has_skills := (
			player != null
			and not player.definition.skills.is_empty()
		)
		skill_button.text = "Skills"
		skill_button.visible = (
			has_skills
			and not _skill_menu_open
		)
		skill_button.disabled = not can_choose_action

	if _skill_menu_open:
		_refresh_skill_menu()
	else:
		call_deferred(
			"_focus_first_command_if_needed"
		)


func _is_command_selection_active() -> bool:
	return (
		battle_controller != null
		and battle_controller.battle_session != null
		and battle_controller.battle_session.phase
			== BattleSession.Phase.COMMAND_SELECTION
	)


func _on_phase_changed(
	new_phase: BattleSession.Phase
) -> void:
	if new_phase == BattleSession.Phase.COMMAND_SELECTION:
		_cancel_target_selection()
		_hide_skill_menu()
		status_label.text = "Choose an action."

	elif new_phase == BattleSession.Phase.RESOLVING:
		_cancel_target_selection()
		_hide_skill_menu()
		status_label.text = (
			"Resolving actions... "
			+ "[Hold E to fast-forward; click or Esc to skip]"
		)

	elif new_phase == BattleSession.Phase.TURN_COMPLETE:
		status_label.text = "Turn complete."

	_refresh()


func _on_active_player_changed(
	player: CombatantState
) -> void:
	_cancel_target_selection()
	_hide_skill_menu()

	if player == null:
		status_label.text = (
			"All actions selected. Starting round..."
		)
	else:
		status_label.text = (
			"%s: choose an action."
			% player.definition.display_name
		)

	_refresh()


func _on_player_action_changed(
	_action: BattleAction
) -> void:
	_refresh()


func _on_timing_requested(
	action: BattleAction,
	target_position: Vector2
) -> void:
	if (
		action == null
		or action.ability == null
	):
		return

	match action.ability.timing_type:
		AbilityDefinition.TimingType.CROSSHAIR_HEAD:
			status_label.text = (
				"Press E or click when the crosshair is over the enemy's head!"
			)

			var hud_target_position: Vector2 = (
				$Root
					.get_screen_transform()
					.affine_inverse()
					* target_position
			)

			_crosshair_minigame.start(
				action,
				hud_target_position
			)

		AbilityDefinition.TimingType.DIRECTION_SEQUENCE:
			status_label.text = (
				"Enter all %d directions before time runs out!"
				% action.ability.timing_input_count
			)
			_direction_minigame.start(
				action,
				action.ability.timing_input_count
			)

		_:
			push_error(
				"BattleHUD: unsupported timing minigame type %d"
				% action.ability.timing_type
			)
			battle_controller.submit_timing_result(
				action,
				BattleAction.TimingResult.NONE
			)


func _on_crosshair_timing_completed(
	action: BattleAction,
	timing_result: BattleAction.TimingResult,
	feedback_text: String
) -> void:
	status_label.text = feedback_text

	if not battle_controller.submit_timing_result(
		action,
		timing_result
	):
		push_error(
			"BattleHUD: timing result was rejected"
		)


func _on_direction_correct_input() -> void:
	if _presentation_director != null:
		_presentation_director.play_timing_impact_shake()


func _on_direction_timing_completed(
	action: BattleAction,
	timing_result: BattleAction.TimingResult,
	feedback_text: String,
	successful_inputs: int
) -> void:
	status_label.text = feedback_text

	if not battle_controller.submit_timing_result(
		action,
		timing_result,
		successful_inputs
	):
		push_error(
			"BattleHUD: direction timing result was rejected"
		)


func _on_action_queued(
	_action: BattleAction
) -> void:
	_refresh()


func _on_action_started(action: BattleAction) -> void:
	if action == null or action.actor == null:
		return

	var actor_name := action.actor.definition.display_name
	var message: String

	if action.ability.kind == AbilityDefinition.Kind.GUARD:
		message = "%s is guarding." % actor_name

	elif (
		action.ability.has_effect_type(
			AbilityEffectDefinition.EffectType.HEAL
		)
	):
		message = (
			"%s used %s."
			% [
				actor_name,
				action.ability.display_name
			]
		)

	elif action.target == null:
		message = (
			"%s used %s."
			% [
				actor_name,
				action.ability.display_name
			]
		)

	else:
		message = (
			"%s %s at %s."
			% [
				actor_name,
				action.ability.action_verb,
				action.target.definition.display_name
			]
		)

	_show_presentation_message(message)


func _show_presentation_message(message: String) -> void:
	_display_presentation_message(message)


func _display_presentation_message(message: String) -> void:
	status_label.text = (
		"%s  [Hold E to fast-forward; click or Esc to skip]"
		% message
	)


func _on_action_cancelled(action: BattleAction) -> void:
	if action == null or action.actor == null:
		return

	if (
		action.ability != null
		and action.ability.is_power_attack
		and action.actor.power_attack_disrupted
	):
		return

	_show_presentation_message(
		"%s's %s was disrupted."
		% [
			action.actor.definition.display_name,
			action.ability.display_name
		]
	)


func _on_effect_presentation_started(
	result: BattleEffectResult
) -> void:
	if result == null or result.target == null:
		return

	if result.missed:
		_show_presentation_message(
			"%s missed."
			% result.source.definition.display_name
		)
		return

	if result.disrupted:
		_show_presentation_message(
			"%s's POWER ATTACK was disrupted!"
			% result.target.definition.display_name
		)
		return

	match result.effect.effect_type:
		AbilityEffectDefinition.EffectType.HEAL, AbilityEffectDefinition.EffectType.REVIVE:
			_show_presentation_message(
				"%s recovered %d HP."
				% [
					result.target.definition.display_name,
					result.amount
				]
			)

		AbilityEffectDefinition.EffectType.GUARD:
			_show_presentation_message(
				"%s braces for impact."
				% result.target.definition.display_name
			)

		AbilityEffectDefinition.EffectType.APPLY_STATUS:
			if result.effect.status != null:
				_show_presentation_message(
					"%s is affected by %s."
					% [
						result.target.definition.display_name,
						result.effect.status.display_name
					]
				)

		AbilityEffectDefinition.EffectType.CLEANSE:
			_show_presentation_message(
				"%s was cleansed."
				% result.target.definition.display_name
			)


func _on_action_presentation_finished(
	_action: BattleAction
) -> void:
	status_label.text = (
		"Resolving actions... "
		+ "[Hold E to fast-forward; click or Esc to skip]"
	)


func _on_power_attack_started(
	enemy: CombatantState
) -> void:
	status_label.text = (
		"%s is preparing a POWER ATTACK!"
		% enemy.definition.display_name
	)

	_refresh()


func _on_battle_won() -> void:
	status_label.text = "BATTLE WON"
	_refresh()


func _on_battle_lost() -> void:
	status_label.text = "BATTLE LOST"
	_refresh()


func _on_enemy_actor_clicked(
	actor: BattleEnemyActor
) -> void:
	if not selecting_attack_target:
		return

	if actor == null or actor.combatant == null:
		return

	if actor.combatant.is_defeated():
		status_label.text = "That enemy has been defeated."
		return

	var ability := _pending_target_ability
	_cancel_target_selection()

	if ability != null:
		battle_controller.choose_skill(
			ability,
			actor.combatant
		)
	else:
		battle_controller.choose_main_attack(
			actor.combatant
		)

	_refresh()


func _create_skill_menu() -> void:
	_skill_menu = HBoxContainer.new()
	_skill_menu.name = "SkillMenu"
	_skill_menu.visible = false
	_skill_menu.add_theme_constant_override(
		"separation",
		12
	)
	attack_button.get_parent().add_child(_skill_menu)


func _create_crosshair_minigame() -> void:
	_crosshair_minigame = (
		CrosshairTimingMinigame.new()
	)
	_crosshair_minigame.name = (
		"CrosshairTimingMinigame"
	)
	$Root.add_child(_crosshair_minigame)
	_crosshair_minigame.configure(
		emm_crosshair_texture,
		battle_controller.attack_action,
		emm_crosshair_speed,
		emm_killshot_radius,
		emm_clean_shot_radius
	)
	_crosshair_minigame.completed.connect(
		_on_crosshair_timing_completed
	)


func _create_direction_minigame() -> void:
	_direction_minigame = (
		DirectionTimingMinigame.new()
	)
	_direction_minigame.name = (
		"DirectionTimingMinigame"
	)
	$Root.add_child(_direction_minigame)
	_direction_minigame.configure(
		roommate_input_time,
		3,
		roommate_punch_sound
	)
	_direction_minigame.correct_input.connect(
		_on_direction_correct_input
	)
	_direction_minigame.completed.connect(
		_on_direction_timing_completed
	)


func _is_timing_minigame_active() -> bool:
	return (
		(
			_crosshair_minigame != null
			and _crosshair_minigame.is_active()
		)
		or (
			_direction_minigame != null
			and _direction_minigame.is_active()
		)
	)


func _show_skill_menu(
	player: CombatantState
) -> void:
	_skill_menu_open = true
	attack_button.visible = false
	skill_button.visible = false
	guard_button.visible = false
	_skill_menu.visible = true
	_populate_skill_menu(player)
	call_deferred("_focus_first_skill_button")

	status_label.text = (
		"%s: choose a skill."
		% player.definition.display_name
	)


func _hide_skill_menu() -> void:
	_skill_menu_open = false
	_skill_menu.visible = false
	attack_button.visible = true
	skill_button.visible = true
	guard_button.visible = true
	call_deferred(
		"_focus_first_command_if_needed"
	)


func _populate_skill_menu(
	player: CombatantState
) -> void:
	for child in _skill_menu.get_children():
		child.free()

	for skill in player.definition.skills:
		if skill == null:
			continue

		var button := Button.new()
		button.custom_minimum_size = Vector2(140.0, 48.0)
		button.text = "%s (%d)" % [
			skill.display_name,
			skill.tempo_cost
		]
		button.disabled = (
			player.current_tempo < skill.tempo_cost
		)
		button.pressed.connect(
			_on_skill_selected.bind(skill)
		)
		_skill_menu.add_child(button)

	var back_button := Button.new()
	back_button.custom_minimum_size = Vector2(110.0, 48.0)
	back_button.text = "Back"
	back_button.pressed.connect(_on_skill_back_pressed)
	_skill_menu.add_child(back_button)
	call_deferred("_focus_first_skill_button")


func _refresh_skill_menu() -> void:
	var player := battle_controller.get_current_player()

	if player == null:
		_hide_skill_menu()
		return

	_populate_skill_menu(player)


func _on_skill_selected(
	ability: AbilityDefinition
) -> void:
	var player := battle_controller.get_current_player()

	if player == null or ability == null:
		return

	if player.current_tempo < ability.tempo_cost:
		status_label.text = (
			"%s needs %d Tempo to use %s."
			% [
				player.definition.display_name,
				ability.tempo_cost,
				ability.display_name
			]
		)
		return

	var needs_enemy := _ability_uses_target_type(
		ability,
		AbilityEffectDefinition.TargetType.SELECTED_ENEMY
	)
	var needs_ally := _ability_uses_target_type(
		ability,
		AbilityEffectDefinition.TargetType.SELECTED_ALLY
	)

	if needs_enemy and needs_ally:
		status_label.text = (
			"%s needs incompatible enemy and ally targets."
			% ability.display_name
		)
		return

	_hide_skill_menu()
	_pending_target_ability = ability

	if needs_enemy:
		selecting_attack_target = true
		_set_enemy_target_selection_enabled(true)
		_select_first_keyboard_enemy()
		status_label.text = (
			"%s: choose an enemy target."
			% ability.display_name
		)
		return

	if needs_ally:
		selecting_ally_target = true
		_select_first_keyboard_ally()
		status_label.text = (
			"%s: choose a party member."
			% ability.display_name
		)
		return

	_pending_target_ability = null
	battle_controller.choose_skill(ability)
	_refresh()


func _on_skill_back_pressed() -> void:
	_hide_skill_menu()

	var player := battle_controller.get_current_player()

	if player != null:
		status_label.text = (
			"%s: choose an action."
			% player.definition.display_name
		)

	_refresh()


func _on_party_card_clicked(
	player: CombatantState
) -> void:
	if not _is_command_selection_active():
		return

	if selecting_ally_target:
		var ability := _pending_target_ability
		_cancel_target_selection()

		if ability != null:
			battle_controller.choose_skill(
				ability,
				player
			)

		_refresh()
		return

	if battle_controller.reselect_player(player):
		_cancel_target_selection()
		_hide_skill_menu()
		status_label.text = (
			"%s: choose a different action."
			% player.definition.display_name
		)
		_refresh()


func _go_back() -> void:
	if battle_controller.return_to_previous_player():
		_cancel_target_selection()
		_hide_skill_menu()

		var player := battle_controller.get_current_player()

		if player != null:
			status_label.text = (
				"%s: choose a different action."
				% player.definition.display_name
			)

		_refresh()
		return

	if selecting_attack_target or selecting_ally_target:
		_cancel_target_selection()
		_hide_skill_menu()

		var player := battle_controller.get_current_player()

		if player != null:
			status_label.text = (
				"%s: choose an action."
				% player.definition.display_name
			)

		_refresh()
		return

	if _skill_menu_open:
		_on_skill_back_pressed()


func _cancel_target_selection() -> void:
	selecting_attack_target = false
	selecting_ally_target = false
	_pending_target_ability = null
	_clear_keyboard_target_selection()
	_set_enemy_target_selection_enabled(false)


func _set_enemy_target_selection_enabled(
	value: bool
) -> void:
	for actor in battle_controller.enemy_actors:
		if actor != null:
			actor.set_target_selection_enabled(value)


func _get_navigation_direction(
	event: InputEvent
) -> int:
	if event is InputEventKey:
		var key_event := event as InputEventKey

		if key_event.echo:
			return 0

	if (
		event.is_action_pressed(&"ui_left")
		or event.is_action_pressed(&"ui_up")
		or event.is_action_pressed(&"move_left")
		or event.is_action_pressed(&"move_up")
	):
		return -1

	if (
		event.is_action_pressed(&"ui_right")
		or event.is_action_pressed(&"ui_down")
		or event.is_action_pressed(&"move_right")
		or event.is_action_pressed(&"move_down")
	):
		return 1

	return 0


func _is_confirm_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey

		if key_event.echo:
			return false

	return (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"ui_accept")
	)


func _move_keyboard_selection(
	direction: int
) -> void:
	if selecting_attack_target:
		var enemies := _get_living_enemy_actors()

		if enemies.is_empty():
			return

		var current_index := enemies.find(
			_keyboard_enemy
		)
		var next_index := _get_wrapped_index(
			current_index,
			direction,
			enemies.size()
		)
		_set_keyboard_enemy(enemies[next_index])
		return

	if selecting_ally_target:
		var allies := _get_living_allies()

		if allies.is_empty():
			return

		var current_index := allies.find(
			_keyboard_ally
		)
		var next_index := _get_wrapped_index(
			current_index,
			direction,
			allies.size()
		)
		_set_keyboard_ally(allies[next_index])
		return

	var buttons := _get_keyboard_buttons()

	if buttons.is_empty():
		return

	var focus_owner := (
		get_viewport().gui_get_focus_owner()
	)
	var current_index := buttons.find(focus_owner)
	var next_index := _get_wrapped_index(
		current_index,
		direction,
		buttons.size()
	)
	buttons[next_index].grab_focus()


func _activate_keyboard_selection() -> void:
	if selecting_attack_target:
		if _keyboard_enemy == null:
			_select_first_keyboard_enemy()

		if _keyboard_enemy != null:
			_on_enemy_actor_clicked(_keyboard_enemy)

		return

	if selecting_ally_target:
		if _keyboard_ally == null:
			_select_first_keyboard_ally()

		if _keyboard_ally != null:
			_on_party_card_clicked(_keyboard_ally)

		return

	var buttons := _get_keyboard_buttons()

	if buttons.is_empty():
		return

	var focus_owner := (
		get_viewport().gui_get_focus_owner()
	)
	var button := focus_owner as Button

	if button == null or not buttons.has(button):
		button = buttons[0]
		button.grab_focus()

	button.emit_signal(&"pressed")


func _get_keyboard_buttons() -> Array[Button]:
	var result: Array[Button] = []

	if _skill_menu_open:
		for child in _skill_menu.get_children():
			var button := child as Button

			if (
				button != null
				and button.visible
				and not button.disabled
			):
				result.append(button)

		return result

	for button in [
		attack_button,
		skill_button,
		guard_button
	]:
		if (
			button != null
			and button.visible
			and not button.disabled
		):
			result.append(button)

	return result


func _get_living_enemy_actors() -> Array[BattleEnemyActor]:
	var result: Array[BattleEnemyActor] = []

	for actor in battle_controller.enemy_actors:
		if (
			actor != null
			and actor.combatant != null
			and not actor.combatant.is_defeated()
		):
			result.append(actor)

	return result


func _get_living_allies() -> Array[CombatantState]:
	var result: Array[CombatantState] = []

	for player in battle_controller.battle_session.player_party:
		if not player.is_defeated():
			result.append(player)

	return result


func _select_first_keyboard_enemy() -> void:
	var enemies := _get_living_enemy_actors()
	_set_keyboard_enemy(
		null if enemies.is_empty() else enemies[0]
	)


func _select_first_keyboard_ally() -> void:
	var allies := _get_living_allies()
	_set_keyboard_ally(
		null if allies.is_empty() else allies[0]
	)


func _set_keyboard_enemy(
	selected_actor: BattleEnemyActor
) -> void:
	_keyboard_enemy = selected_actor

	for actor in battle_controller.enemy_actors:
		if actor != null:
			actor.set_keyboard_selected(
				actor == _keyboard_enemy
			)


func _set_keyboard_ally(
	selected_player: CombatantState
) -> void:
	_keyboard_ally = selected_player

	for player in _party_cards:
		var card := (
			_party_cards[player]
			as BattlePartyCard
		)

		if card != null:
			card.set_keyboard_selected(
				player == _keyboard_ally
			)


func _clear_keyboard_target_selection() -> void:
	_set_keyboard_enemy(null)
	_set_keyboard_ally(null)


func _get_wrapped_index(
	current_index: int,
	direction: int,
	option_count: int
) -> int:
	if option_count <= 0:
		return -1

	if current_index < 0:
		return 0 if direction >= 0 else option_count - 1

	return posmod(
		current_index + direction,
		option_count
	)


func _focus_first_command_if_needed() -> void:
	if (
		not _is_command_selection_active()
		or _skill_menu_open
		or selecting_attack_target
		or selecting_ally_target
	):
		return

	var buttons := _get_keyboard_buttons()

	if not buttons.is_empty():
		buttons[0].grab_focus()


func _focus_first_skill_button() -> void:
	if not _skill_menu_open:
		return

	var buttons := _get_keyboard_buttons()

	if not buttons.is_empty():
		buttons[0].grab_focus()


func _ability_uses_target_type(
	ability: AbilityDefinition,
	target_type: AbilityEffectDefinition.TargetType
) -> bool:
	for effect in ability.effects:
		if (
			effect != null
			and effect.target_type == target_type
		):
			return true

	return false
