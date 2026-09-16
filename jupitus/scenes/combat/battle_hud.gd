extends CanvasLayer
class_name BattleHUD

@export var battle_controller: BattleController

@onready var target_prompt: Label = $Root/ScreenMargin/Layout/TargetPrompt
@onready var party_list: HBoxContainer = $Root/ScreenMargin/Layout/PartyList
@onready var attack_button: Button = $Root/ScreenMargin/Layout/CommandBar/AttackButton
@onready var guard_button: Button = $Root/ScreenMargin/Layout/CommandBar/GuardButton
@onready var confirm_button: Button = $Root/ScreenMargin/Layout/CommandBar/ConfirmButton
@onready var status_label: Label = $Root/ScreenMargin/Layout/StatusLabel

var _refresh_pending: bool = false

var selecting_attack_target: bool = false


func _ready() -> void:
	if battle_controller == null:
		push_error("BattleHUD: assign a BattleController in the Inspector")
		return

	attack_button.pressed.connect(_on_attack_pressed)
	guard_button.pressed.connect(_on_guard_pressed)
	confirm_button.pressed.connect(_on_confirm_pressed)

	call_deferred("_connect_to_battle")


func _connect_to_battle() -> void:
	if battle_controller == null or battle_controller.battle_session == null:
		push_error("BattleHUD: BattleController has no BattleSession")
		return

	var session: BattleSession = battle_controller.battle_session

	session.phase_changed.connect(_on_phase_changed)
	session.action_queued.connect(_on_action_queued)
	session.damage_applied.connect(_on_damage_applied)
	session.power_attack_started.connect(_on_power_attack_started)
	session.power_attack_disrupted.connect(_on_power_attack_disrupted)
	session.battle_won.connect(_on_battle_won)
	session.battle_lost.connect(_on_battle_lost)

	battle_controller.player_action_changed.connect(
		_on_player_action_changed
	)
	for actor in battle_controller.enemy_actors:
		if actor == null:
			continue

		if not actor.clicked.is_connected(_on_enemy_actor_clicked):
			actor.clicked.connect(_on_enemy_actor_clicked)

	_refresh()
	battle_controller.start_battle()
	


func _on_attack_pressed() -> void:
	if not _is_command_selection_active():
		return

	if battle_controller.selected_player_action != null:
		return

	selecting_attack_target = true
	target_prompt.text = "Select an enemy target"
	status_label.text = "Choose an enemy."


func _on_guard_pressed() -> void:
	if not _is_command_selection_active():
		return

	selecting_attack_target = false
	battle_controller.choose_guard()
	_refresh()


func _on_confirm_pressed() -> void:
	if not _is_command_selection_active():
		return

	if battle_controller.selected_player_action == null:
		status_label.text = "Choose Attack or Guard first."
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

	if battle_controller == null or battle_controller.battle_session == null:
		return

	_refresh_party()
	_refresh_commands()


func _refresh_party() -> void:
	_clear_container(party_list)

	for player in battle_controller.battle_session.player_party:
		var card := HBoxContainer.new()
		card.custom_minimum_size = Vector2(300.0, 120.0)
		card.add_theme_constant_override("separation", 12)

		var icon := TextureRect.new()
		icon.texture = player.definition.icon
		icon.custom_minimum_size = Vector2(96.0, 96.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card.add_child(icon)

		var stats := VBoxContainer.new()
		stats.custom_minimum_size = Vector2(190.0, 0.0)
		stats.add_theme_constant_override("separation", 4)
		card.add_child(stats)

		var name_label := Label.new()
		name_label.text = player.definition.display_name
		name_label.add_theme_font_size_override("font_size", 22)
		name_label.add_theme_color_override("font_color", Color("#202020"))
		stats.add_child(name_label)

		stats.add_child(_make_stat_row(
			"HP:",
			player.current_hp,
			player.definition.max_hp,
			Color("#62D84E")
		))

		stats.add_child(_make_stat_row(
			"TEMPO:",
			player.current_tempo,
			player.definition.max_tempo,
			Color("#E5A24E")
		))

		party_list.add_child(card)


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
	value_label.text = "%d/%d" % [current_value, max_value]
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

func _refresh_commands() -> void:
	var command_active := _is_command_selection_active()
	var action_selected := (
		battle_controller.selected_player_action != null
	)

	attack_button.disabled = not command_active or action_selected
	guard_button.disabled = not command_active or action_selected
	confirm_button.disabled = not command_active or not action_selected

	target_prompt.visible = selecting_attack_target



func _get_party_text(player: CombatantState) -> String:
	var text := player.definition.display_name

	text += "\nHP: %d/%d" % [
		player.current_hp,
		player.definition.max_hp
	]

	text += "\nTEMPO: %d/%d" % [
		player.current_tempo,
		player.definition.max_tempo
	]

	if player.is_guarding:
		text += "\nGUARDING"

	if player.is_defeated():
		text += "\nDEFEATED"

	return text


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


func _on_phase_changed(new_phase: BattleSession.Phase) -> void:
	if new_phase == BattleSession.Phase.COMMAND_SELECTION:
		selecting_attack_target = false
		status_label.text = "Choose an action."

	elif new_phase == BattleSession.Phase.RESOLVING:
		status_label.text = "Resolving actions..."

	elif new_phase == BattleSession.Phase.TURN_COMPLETE:
		status_label.text = "Turn complete."

	_refresh()


func _on_player_action_changed(_action: BattleAction) -> void:
	status_label.text = "Action selected. Confirm the turn."
	_refresh()


func _on_action_queued(_action: BattleAction) -> void:
	_refresh()


func _on_damage_applied(
	_action: BattleAction,
	_target: CombatantState,
	_amount: int
) -> void:
	_refresh()


func _on_power_attack_started(enemy: CombatantState) -> void:
	status_label.text = "%s is preparing a POWER ATTACK!" % enemy.definition.display_name
	_refresh()


func _on_power_attack_disrupted(enemy: CombatantState) -> void:
	status_label.text = "%s's POWER ATTACK was disrupted!" % enemy.definition.display_name
	_refresh()


func _on_battle_won() -> void:
	status_label.text = "BATTLE WON"
	_refresh()


func _on_battle_lost() -> void:
	status_label.text = "BATTLE LOST"
	_refresh()
	
	
func _on_enemy_actor_clicked(actor: BattleEnemyActor) -> void:
	if not selecting_attack_target:
		status_label.text = "Press Attack before selecting a target."
		return

	if actor == null or actor.combatant == null:
		return

	if actor.combatant.is_defeated():
		status_label.text = "That enemy has been defeated."
		return

	selecting_attack_target = false
	battle_controller.choose_main_attack(actor.combatant)
	_refresh()
