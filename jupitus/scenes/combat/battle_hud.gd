extends CanvasLayer
class_name BattleHUD

@export var battle_controller: BattleController

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

var _hp_bars: Dictionary = {}
var _hp_value_labels: Dictionary = {}
var _tempo_bars: Dictionary = {}
var _tempo_value_labels: Dictionary = {}


func _ready() -> void:
	if battle_controller == null:
		push_error(
			"BattleHUD: assign a BattleController in the Inspector"
		)
		return

	attack_button.pressed.connect(_on_attack_pressed)
	skill_button.pressed.connect(_on_skill_pressed)
	guard_button.pressed.connect(_on_guard_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

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

	if not session.damage_applied.is_connected(
		_on_damage_applied
	):
		session.damage_applied.connect(_on_damage_applied)

	if not session.healing_applied.is_connected(
		_on_healing_applied
	):
		session.healing_applied.connect(_on_healing_applied)

	if not session.power_attack_started.is_connected(
		_on_power_attack_started
	):
		session.power_attack_started.connect(
			_on_power_attack_started
		)

	if not session.power_attack_disrupted.is_connected(
		_on_power_attack_disrupted
	):
		session.power_attack_disrupted.connect(
			_on_power_attack_disrupted
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


func _input(event: InputEvent) -> void:
	if battle_controller == null:
		return

	if battle_controller.battle_session == null:
		return

	if (
		battle_controller.battle_session.phase
		!= BattleSession.Phase.RESOLVING
	):
		return

	var should_skip := false

	if event.is_action_pressed("interact"):
		should_skip = true

	elif event.is_action_pressed("ui_accept"):
		should_skip = true

	elif event is InputEventMouseButton:
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

	status_label.text = (
		"%s: choose an enemy target."
		% player.definition.display_name
	)

	_refresh()


func _on_skill_pressed() -> void:
	if not _is_command_selection_active():
		return

	var player := battle_controller.get_current_player()
	var skill := _get_current_skill()

	if player == null or skill == null:
		return

	if player.current_tempo < skill.tempo_cost:
		status_label.text = (
			"%s needs %d Tempo to use %s."
			% [
				player.definition.display_name,
				skill.tempo_cost,
				skill.display_name
			]
		)
		return

	battle_controller.choose_skill(
		skill,
		player
	)

	_refresh()


func _on_guard_pressed() -> void:
	if not _is_command_selection_active():
		return

	selecting_attack_target = false
	battle_controller.choose_guard()
	_refresh()


func _on_confirm_pressed() -> void:
	if not _is_command_selection_active():
		return

	if not battle_controller.all_player_actions_selected():
		var player := battle_controller.get_current_player()

		if player != null:
			status_label.text = (
				"%s still needs to choose an action."
				% player.definition.display_name
			)
		else:
			status_label.text = (
				"Every living character must choose an action."
			)

		return

	selecting_attack_target = false
	battle_controller.confirm_turn()
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
	_hp_bars.clear()
	_hp_value_labels.clear()
	_tempo_bars.clear()
	_tempo_value_labels.clear()

	_clear_container(party_list)

	var active_player := battle_controller.get_current_player()

	for player in battle_controller.battle_session.player_party:
		var card := HBoxContainer.new()

		card.custom_minimum_size = Vector2(300.0, 120.0)
		card.add_theme_constant_override("separation", 12)

		if player == active_player:
			card.modulate = Color("#FFF0B0")
		else:
			card.modulate = Color.WHITE

		var icon := TextureRect.new()
		icon.texture = player.definition.icon
		icon.custom_minimum_size = Vector2(96.0, 96.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.pivot_offset = Vector2(48.0, 48.0)

		_animate_party_icon(icon)

		card.add_child(icon)

		var stats := VBoxContainer.new()
		stats.custom_minimum_size = Vector2(190.0, 0.0)
		stats.add_theme_constant_override("separation", 4)
		card.add_child(stats)

		var name_label := Label.new()
		name_label.text = player.definition.display_name
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override(
			"font_color",
			Color("#202020")
		)
		stats.add_child(name_label)

		var hp_row := _make_stat_row(
			"HP:",
			player.current_hp,
			player.definition.max_hp,
			Color("#62D84E")
		)

		stats.add_child(hp_row)

		_hp_bars[player] = (
			hp_row.get_child(1) as ProgressBar
		)

		_hp_value_labels[player] = (
			hp_row.get_child(2) as Label
		)

		var tempo_row := _make_stat_row(
			"TEMPO:",
			player.current_tempo,
			player.definition.max_tempo,
			Color("#E5A24E")
		)

		stats.add_child(tempo_row)

		_tempo_bars[player] = (
			tempo_row.get_child(1) as ProgressBar
		)

		_tempo_value_labels[player] = (
			tempo_row.get_child(2) as Label
		)

		if player.is_guarding:
			var guard_label := Label.new()
			guard_label.text = "GUARDING"
			stats.add_child(guard_label)

		if player.is_defeated():
			var defeated_label := Label.new()
			defeated_label.text = "DEFEATED"
			stats.add_child(defeated_label)

		party_list.add_child(card)


func _animate_party_icon(icon: TextureRect) -> void:
	var tween := icon.create_tween()

	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		icon,
		"rotation_degrees",
		-3.0,
		0.9
	)

	tween.tween_property(
		icon,
		"rotation_degrees",
		3.0,
		1.8
	)

	tween.tween_property(
		icon,
		"rotation_degrees",
		0.0,
		0.9
	)


func _make_stat_row(
	label_text: String,
	current_value: int,
	max_value: int,
	fill_color: Color
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150.0, 20.0)
	bar.max_value = max_value
	bar.value = current_value
	bar.show_percentage = false

	bar.add_theme_stylebox_override(
		"background",
		_make_bar_style(Color("#D8D8D8"))
	)

	bar.add_theme_stylebox_override(
		"fill",
		_make_bar_style(fill_color)
	)

	row.add_child(bar)

	var value_label := Label.new()
	value_label.text = "%d/%d" % [
		current_value,
		max_value
	]
	value_label.custom_minimum_size = Vector2(65.0, 0.0)
	row.add_child(value_label)

	return row


func _make_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	return style


func _get_current_skill() -> AbilityDefinition:
	var player := battle_controller.get_current_player()

	if player == null:
		return null

	if player.definition.skills.is_empty():
		return null

	return player.definition.skills[0]


func _refresh_commands() -> void:
	var command_active := _is_command_selection_active()
	var player := battle_controller.get_current_player()
	var skill := _get_current_skill()

	var can_choose_action := (
		command_active
		and player != null
	)

	attack_button.disabled = (
		not can_choose_action
		or selecting_attack_target
	)

	guard_button.disabled = not can_choose_action

	if skill_button != null:
		skill_button.visible = skill != null

		if skill != null:
			skill_button.text = (
				"%s (%d)"
				% [
					skill.display_name,
					skill.tempo_cost
				]
			)

			skill_button.disabled = (
				not can_choose_action
				or player.current_tempo < skill.tempo_cost
			)

	confirm_button.disabled = (
		not command_active
		or not battle_controller.all_player_actions_selected()
	)


func _is_command_selection_active() -> bool:
	return (
		battle_controller != null
		and battle_controller.battle_session != null
		and battle_controller.battle_session.phase
			== BattleSession.Phase.COMMAND_SELECTION
	)


func _clear_container(container: Container) -> void:
	for child in container.get_children():
		child.free()


func _on_phase_changed(
	new_phase: BattleSession.Phase
) -> void:
	if new_phase == BattleSession.Phase.COMMAND_SELECTION:
		selecting_attack_target = false
		status_label.text = "Choose an action."

	elif new_phase == BattleSession.Phase.RESOLVING:
		selecting_attack_target = false
		status_label.text = "Resolving actions..."

	elif new_phase == BattleSession.Phase.TURN_COMPLETE:
		status_label.text = "Turn complete."

	_refresh()


func _on_active_player_changed(
	player: CombatantState
) -> void:
	selecting_attack_target = false

	if player == null:
		status_label.text = (
			"All actions selected. Confirm the turn."
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
		action.ability.effect_type
		== AbilityDefinition.EffectType.HEAL
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
	status_label.text = (
		"%s  [Click or press E to continue]"
		% message
	)


func _on_action_cancelled(action: BattleAction) -> void:
	if action == null or action.actor == null:
		return

	_show_presentation_message(
		"%s's %s was disrupted."
		% [
			action.actor.definition.display_name,
			action.ability.display_name
		]
	)


func _on_damage_applied(
	_action: BattleAction,
	target: CombatantState,
	amount: int
) -> void:
	_show_damage_number(target, amount)
	_animate_health_bar(target)


func _on_healing_applied(
	_action: BattleAction,
	target: CombatantState,
	amount: int
) -> void:
	_show_presentation_message(
		"%s recovered %d HP."
		% [
			target.definition.display_name,
			amount
		]
	)

	_animate_health_bar(target)


func _show_damage_number(
	target: CombatantState,
	amount: int
) -> void:
	for actor in battle_controller.enemy_actors:
		if actor == null:
			continue

		if actor.combatant == target:
			actor.show_damage_number(amount)
			return


func _animate_health_bar(target: CombatantState) -> void:
	var hp_bar := _hp_bars.get(target) as ProgressBar
	var hp_label := _hp_value_labels.get(target) as Label

	if hp_bar == null:
		_refresh()
		return

	var tween := create_tween()

	tween.tween_property(
		hp_bar,
		"value",
		target.current_hp,
		0.55
	).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)

	if hp_label != null:
		hp_label.text = "%d/%d" % [
			target.current_hp,
			target.definition.max_hp
		]

	var tempo_bar := _tempo_bars.get(target) as ProgressBar
	var tempo_label := _tempo_value_labels.get(target) as Label

	if tempo_bar != null:
		tempo_bar.value = target.current_tempo

	if tempo_label != null:
		tempo_label.text = "%d/%d" % [
			target.current_tempo,
			target.definition.max_tempo
		]


func _on_power_attack_started(
	enemy: CombatantState
) -> void:
	status_label.text = (
		"%s is preparing a POWER ATTACK!"
		% enemy.definition.display_name
	)

	_refresh()


func _on_power_attack_disrupted(
	enemy: CombatantState
) -> void:
	status_label.text = (
		"%s's POWER ATTACK was disrupted!"
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
		status_label.text = (
			"Press Attack before selecting a target."
		)
		return

	if actor == null or actor.combatant == null:
		return

	if actor.combatant.is_defeated():
		status_label.text = "That enemy has been defeated."
		return

	selecting_attack_target = false

	battle_controller.choose_main_attack(
		actor.combatant
	)

	_refresh()
