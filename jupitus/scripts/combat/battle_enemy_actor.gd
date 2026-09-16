extends Node2D
class_name BattleEnemyActor

signal clicked(actor: BattleEnemyActor)
signal hover_started(actor: BattleEnemyActor)
signal hover_ended(actor: BattleEnemyActor)

@export_group("Scene Nodes")
@export var visual_node: NodePath = ^"Visual"
@export var target_area: NodePath = ^"TargetArea"
@export var power_attack_indicator: NodePath = ^"PowerAttackIndicator"

@export_group("Defeat")
@export var hide_when_defeated: bool = false
@export var defeated_modulate: Color = Color(0.45, 0.45, 0.45, 1.0)

@export_group("Hover")
@export var hover_scale_multiplier: float = 1.05

var combatant: CombatantState = null
var _base_scale: Vector2

@onready var _visual: CanvasItem = (
	get_node_or_null(visual_node) as CanvasItem
)

@onready var _target_area: Area2D = (
	get_node_or_null(target_area) as Area2D
)

@onready var _power_attack_indicator: CanvasItem = (
	get_node_or_null(power_attack_indicator) as CanvasItem
)


func _ready() -> void:
	_base_scale = scale

	if _target_area == null:
		push_warning(
			"BattleEnemyActor '%s' has no TargetArea assigned"
			% name
		)
		return

	_target_area.input_pickable = true
	_target_area.collision_layer = 1

	_target_area.input_event.connect(_on_target_area_input_event)
	_target_area.mouse_entered.connect(_on_target_area_mouse_entered)
	_target_area.mouse_exited.connect(_on_target_area_mouse_exited)


func bind_combatant(value: CombatantState) -> void:
	combatant = value
	sync_from_state()


func sync_from_state() -> void:
	if combatant == null:
		return

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
			_visual.modulate = defeated_modulate
	else:
		_visual.visible = true
		_visual.modulate = Color.WHITE


func _on_target_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_index: int
) -> void:
	if combatant == null or combatant.is_defeated():
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		):
			clicked.emit(self)
			get_viewport().set_input_as_handled()


func _on_target_area_mouse_entered() -> void:
	scale = _base_scale * hover_scale_multiplier
	hover_started.emit(self)


func _on_target_area_mouse_exited() -> void:
	scale = _base_scale
	hover_ended.emit(self)
