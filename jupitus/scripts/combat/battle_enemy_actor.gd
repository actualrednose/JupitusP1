extends Node2D
class_name BattleEnemyActor

signal clicked(actor: BattleEnemyActor)
signal hover_started(actor: BattleEnemyActor)
signal hover_ended(actor: BattleEnemyActor)

@export_group("Scene Nodes")
@export var visual_node: NodePath = ^"Visual"
@export var target_area: NodePath = ^"TargetArea"
@export var power_attack_indicator: NodePath = ^"PowerAttackIndicator"

## Optional Label node used to show the selected action and intent category.
## If the path is empty or missing, a simple label is created automatically.
@export var intent_label: NodePath = ^"IntentLabel"

@export_group("Defeat")
@export var hide_when_defeated: bool = false

@export var defeated_modulate: Color = Color(
	0.45,
	0.45,
	0.45,
	1.0
)

@export_group("Hover")
@export var hover_scale_multiplier: float = 1.05

@export_group("Timing Minigame")
## Marker placed over the enemy's head for crosshair timing attacks.
@export var timing_target: Marker2D

var combatant: CombatantState = null
var target_selection_enabled: bool = false

var _base_scale: Vector2
var _intent: EnemyActionIntent = null
var _debug_intent_visible: bool = false
var _feedback := BattleActorView.new()

@onready var _visual: CanvasItem = (
	get_node_or_null(visual_node) as CanvasItem
)

@onready var _target_area: Area2D = (
	get_node_or_null(target_area) as Area2D
)

@onready var _power_attack_indicator: CanvasItem = (
	get_node_or_null(
		power_attack_indicator
	) as CanvasItem
)

@onready var _intent_label: Label = (
	get_node_or_null(intent_label) as Label
)


func _ready() -> void:
	_base_scale = scale
	_ensure_intent_label()
	_refresh_intent_label()

	_feedback.setup(
		self,
		_visual,
		self,
		Vector2(-24.0, -160.0)
	)

	if _target_area == null:
		push_warning(
			"BattleEnemyActor '%s' has no TargetArea assigned"
			% name
		)
		return

	_target_area.input_pickable = (
		target_selection_enabled
	)

	_target_area.collision_layer = 1

	_target_area.input_event.connect(
		_on_target_area_input_event
	)

	_target_area.mouse_entered.connect(
		_on_target_area_mouse_entered
	)

	_target_area.mouse_exited.connect(
		_on_target_area_mouse_exited
	)


func bind_combatant(
	value: CombatantState
) -> void:
	combatant = value
	sync_from_state()


func set_intent(
	value: EnemyActionIntent
) -> void:
	_intent = value
	_ensure_intent_label()
	_refresh_intent_label()


func set_debug_intent_visible(
	value: bool
) -> void:
	_debug_intent_visible = value
	_refresh_intent_label()


func set_target_selection_enabled(
	value: bool
) -> void:
	target_selection_enabled = value

	if _target_area != null:
		_target_area.input_pickable = value

	if not value:
		scale = _base_scale


func sync_from_state() -> void:
	if combatant == null:
		return

	_feedback.skip_and_reset()

	if _power_attack_indicator:
		_power_attack_indicator.visible = (
			combatant.is_preparing_power_attack
		)

	if _visual == null:
		return

	if combatant.is_defeated():
		if hide_when_defeated:
			_visual.visible = false
		else:
			_visual.visible = true
			_visual.modulate = (
				defeated_modulate
			)
	else:
		_visual.visible = true
		_visual.modulate = Color.WHITE

	_feedback.recapture_base_modulate()


func _ensure_intent_label() -> void:
	if _intent_label != null:
		return

	_intent_label = Label.new()
	_intent_label.name = "IntentLabel"

	_intent_label.position = Vector2(
		-90.0,
		-245.0
	)

	_intent_label.custom_minimum_size = Vector2(
		180.0,
		28.0
	)

	_intent_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)

	_intent_label.add_theme_font_size_override(
		"font_size",
		18
	)

	_intent_label.add_theme_color_override(
		"font_color",
		Color("#FFE49A")
	)

	add_child(_intent_label)


func _refresh_intent_label() -> void:
	if _intent_label == null:
		return

	if (
		_intent == null
		or not _debug_intent_visible
	):
		_intent_label.visible = false
		_intent_label.text = ""
		return

	_intent_label.visible = true

	_intent_label.text = "%s: %s" % [
		_intent.get_category_name(),
		_intent.display_text
	]


func get_presentation_position() -> Vector2:
	return _feedback.get_presentation_position()


func get_timing_target_position() -> Vector2:
	if timing_target != null:
		return (
			timing_target
			.get_screen_transform()
			.origin
		)

	push_warning(
		"BattleEnemyActor '%s' has no timing target assigned"
		% name
	)

	return get_screen_transform().origin


func play_anticipation(
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_anticipation(
		duration,
		reduced_motion
	)


func play_attack(
	target_position: Vector2,
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_attack(
		target_position,
		duration,
		reduced_motion
	)


func play_hit(
	direction: Vector2,
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_hit(
		direction,
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_guard(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_guard(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_heal(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_heal(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_interrupt(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_interrupt(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_power_charge(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_power_charge(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_defeat(
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_defeat(
		duration,
		reduced_motion
	)


func play_recovery(
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_recovery(
		duration,
		reduced_motion
	)


func show_damage_number(
	amount: int,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(
		str(amount),
		Color("#FF6B6B"),
		reduced_motion
	)


func show_healing_number(
	amount: int,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(
		"+%d" % amount,
		Color("#72F58A"),
		reduced_motion
	)


func show_tempo_change(
	amount: int,
	reduced_motion: bool = false
) -> void:
	var prefix := (
		"+" if amount >= 0 else ""
	)

	_feedback.show_number(
		"%s%d TEMPO" % [
			prefix,
			amount
		],
		Color("#F4B65F"),
		reduced_motion
	)


func show_result_text(
	text: String,
	color: Color,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(
		text,
		color,
		reduced_motion
	)


func animate_result(
	_result: BattleEffectResult,
	_duration: float
) -> void:
	pass


func pulse_tempo(
	_amount: int,
	_duration: float,
	_reduced_motion: bool,
	_reduced_flashing: bool
) -> void:
	pass


func skip_presentation() -> void:
	_feedback.skip_and_reset()


func _on_target_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int
) -> void:
	if (
		not target_selection_enabled
		or combatant == null
		or combatant.is_defeated()
	):
		return

	if event is InputEventMouseButton:
		var mouse_event := (
			event as InputEventMouseButton
		)

		if (
			mouse_event.button_index
				== MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		):
			clicked.emit(self)
			get_viewport().set_input_as_handled()


func _on_target_area_mouse_entered() -> void:
	if not target_selection_enabled:
		return

	scale = _base_scale * hover_scale_multiplier
	hover_started.emit(self)


func _on_target_area_mouse_exited() -> void:
	scale = _base_scale
	hover_ended.emit(self)
