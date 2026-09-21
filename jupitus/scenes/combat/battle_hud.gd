extends CanvasLayer
class_name BattleHUD

@export var battle_controller: BattleController

@export_group("Emm Crosshair Timing")
## Assign Emm's crosshair image here after importing it.
## A simple temporary crosshair is drawn when this is empty.
@export var emm_crosshair_texture: Texture2D

## Horizontal travel speed in screen pixels per second.
@export_range(
	100.0,
	1600.0,
	10.0
) var emm_crosshair_speed: float = 500.0

## Maximum horizontal distance from the head for a Killshot.
@export_range(
	1.0,
	100.0,
	1.0
) var emm_killshot_radius: float = 24.0

## Maximum horizontal distance from the head for a Clean shot.
@export_range(
	1.0,
	240.0,
	1.0
) var emm_clean_shot_radius: float = 72.0

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


func _ready() -> void:
	if battle_controller == null:
		push_error(
			"BattleHUD: assign a BattleController in the Inspector"
		)
		return

	attack_button.pressed.connect(
		_on_attack_pressed
	)

	skill_button.pressed.connect(
		_on_skill_pressed
	)

	guard_button.pressed.connect(
		_on_guard_pressed
	)

	confirm_button.visible = false

	_create_skill_menu()
	_create_crosshair_minigame()

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
		session.phase_changed.connect(
			_on_phase_changed
		)

	if not session.action_queued.is_connected(
		_on_action_queued
	):
		session.action_queued.connect(
			_on_action_queued
		)

	if not session.action_started.is_connected(
		_on_action_started
	):
		session.action_started.connect(
			_on_action_started
		)

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
		session.battle_won.connect(
			_on_battle_won
		)

	if not session.battle_lost.is_connected(
		_on_battle_lost
	):
		session.battle_lost.connect(
			_on_battle_lost
		)

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

	if (
		_crosshair_minigame != null
		and _crosshair_minigame.is_active()
	):
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

	if (
		_crosshair_minigame != null
		and _crosshair_minigame.is_active()
	):
		if _crosshair_minigame.handle_input(event):
			get_viewport().set_input_as_handled()

		return

	var phase := battle_controller.battle_session.phase

	if phase == BattleSession.Phase.COMMAND_SELECTION:
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

	var should_skip := (
		event.is_action_pressed("ui_cancel")
	)

	if event is InputEventMouseButton:
		var mouse_event := (
			event as InputEventMouseButton
		)

		if (
			mouse_event.button_index
				== MOUSE_BUTTON_LEFT
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

	var player := (
		battle_controller.get_current_player()
	)

	if player == null:
		return

	selecting_attack_target = true
	selecting_ally_target = false
	_pending_target_ability = null

	_hide_skill_menu()
	_set_enemy_target_selection_enabled(true)

	status_label.text = (
		"%s: choose an enemy target."
		% player.definition.display_name
	)

	_refresh()


func _on_skill_pressed() -> void:
	if not _is_command_selection_active():
		return

	var player := (
		battle_controller.get_current_player()
	)

	if (
		player == null
		or player.definition.skills.is_empty()
	):
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
	var active_player := (
		battle_controller.get_current_player()
	)

	for player in battle_controller.battle_session.player_party:
		var card := (
			_party_cards.get(player)
			as BattlePartyCard
		)

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

		card.set_active(
			player == active_player
		)

		card.set_selected_action(
			battle_controller.selected_player_actions.get(
				player
			) as BattleAction
		)

		card.sync_from_state()


func _refresh_commands() -> void:
	var command_active := (
		_is_command_selection_active()
	)

	var player := (
		battle_controller.get_current_player()
	)

	var can_choose_action := (
		command_active
		and player != null
	)

	attack_button.visible = (
		not _skill_menu_open
	)

	attack_button.disabled = (
		not can_choose_action
		or selecting_attack_target
	)

	guard_button.visible = (
		not _skill_menu_open
	)

	guard_button.disabled = (
		not can_choose_action
	)

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

		skill_button.disabled = (
			not can_choose_action
		)

	if _skill_menu_open:
		_refresh_skill_menu()


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
	if (
		new_phase
		== BattleSession.Phase.COMMAND_SELECTION
	):
		_cancel_target_selection()
		_hide_skill_menu()
		status_label.text = "Choose an action."

	elif (
		new_phase
		== BattleSession.Phase.RESOLVING
	):
		_cancel_target_selection()
		_hide_skill_menu()

		status_label.text = (
			"Resolving actions... "
			+ "[Hold E to fast-forward; "
			+ "click or Esc to skip]"
		)

	elif (
		new_phase
		== BattleSession.Phase.TURN_COMPLETE
	):
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


func _on_action_queued(
	_action: BattleAction
) -> void:
	_refresh()


func _on_action_started(
	action: BattleAction
) -> void:
	if action == null or action.actor == null:
		return

	var actor_name := (
		action.actor.definition.display_name
	)

	var message: String

	if (
		action.ability.kind
		== AbilityDefinition.Kind.GUARD
	):
		message = (
			"%s is guarding."
			% actor_name
		)

	elif action.ability.has_effect_type(
		AbilityEffectDefinition.EffectType.HEAL
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


func _show_presentation_message(
	message: String
) -> void:
	_display_presentation_message(message)


func _display_presentation_message(
	message: String
) -> void:
	status_label.text = (
		"%s  [Hold E to fast-forward; "
		+ "click or Esc to skip]"
	) % message


func _on_action_cancelled(
	action: BattleAction
) -> void:
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
		+ "[Hold E to fast-forward; "
		+ "click or Esc to skip]"
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

	if (
		actor == null
		or actor.combatant == null
	):
		return

	if actor.combatant.is_defeated():
		status_label.text = (
			"That enemy has been defeated."
		)
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

	attack_button.get_parent().add_child(
		_skill_menu
	)


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


func _show_skill_menu(
	player: CombatantState
) -> void:
	_skill_menu_open = true
	attack_button.visible = false
	skill_button.visible = false
	guard_button.visible = false
	_skill_menu.visible = true

	_populate_skill_menu(player)

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


func _populate_skill_menu(
	player: CombatantState
) -> void:
	for child in _skill_menu.get_children():
		child.free()

	for skill in player.definition.skills:
		if skill == null:
			continue

		var button := Button.new()

		button.custom_minimum_size = Vector2(
			140.0,
			48.0
		)

		button.text = "%s (%d)" % [
			skill.display_name,
			skill.tempo_cost
		]

		button.disabled = (
			player.current_tempo
			< skill.tempo_cost
		)

		button.pressed.connect(
			_on_skill_selected.bind(skill)
		)

		_skill_menu.add_child(button)

	var back_button := Button.new()

	back_button.custom_minimum_size = Vector2(
		110.0,
		48.0
	)

	back_button.text = "Back"

	back_button.pressed.connect(
		_on_skill_back_pressed
	)

	_skill_menu.add_child(back_button)


func _refresh_skill_menu() -> void:
	var player := (
		battle_controller.get_current_player()
	)

	if player == null:
		_hide_skill_menu()
		return

	_populate_skill_menu(player)


func _on_skill_selected(
	ability: AbilityDefinition
) -> void:
	var player := (
		battle_controller.get_current_player()
	)

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

		_set_enemy_target_selection_enabled(
			true
		)

		status_label.text = (
			"%s: choose an enemy target."
			% ability.display_name
		)
		return

	if needs_ally:
		selecting_ally_target = true

		status_label.text = (
			"%s: choose a party member."
			% ability.display_name
		)
		return

	_pending_target_ability = null

	battle_controller.choose_skill(
		ability
	)

	_refresh()


func _on_skill_back_pressed() -> void:
	_hide_skill_menu()

	var player := (
		battle_controller.get_current_player()
	)

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

		var player := (
			battle_controller.get_current_player()
		)

		if player != null:
			status_label.text = (
				"%s: choose a different action."
				% player.definition.display_name
			)

		_refresh()
		return

	if (
		selecting_attack_target
		or selecting_ally_target
	):
		_cancel_target_selection()
		_hide_skill_menu()

		var player := (
			battle_controller.get_current_player()
		)

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

	_set_enemy_target_selection_enabled(false)


func _set_enemy_target_selection_enabled(
	value: bool
) -> void:
	for actor in battle_controller.enemy_actors:
		if actor != null:
			actor.set_target_selection_enabled(
				value
			)


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
