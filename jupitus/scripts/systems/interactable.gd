# interactable.gd
# -----------------------------------------------------------------------------
# Attach to: Area3D
#
# Extend this class to make NPCs, signs, doors, items, levers, and other
# objects the player can interact with.
#
# Required setup:
#   Area3D
#   └── CollisionShape3D
#
# Collision convention:
#   - Player body: layer 1
#   - Interactable: layer 2
#   - Interactable collision mask includes layer 1
# -----------------------------------------------------------------------------

extends Area3D
class_name Interactable


# -----------------------------------------------------------------------------
# Tweakable values
# -----------------------------------------------------------------------------

@export_group("Prompt")

## Text shown above the object while the player is in range.
@export var prompt_text: String = "Press E"

## Height of the prompt above this Area3D's origin.
@export var prompt_height: float = 1.2

## Font size used by the automatically created Label3D.
@export var prompt_font_size: int = 32


@export_group("Input")

## Input action used to interact with this object.
@export var input_action: StringName = &"interact"


@export_group("Behavior")

## When false, interaction input and prompts are disabled.
##
## The Area3D still remembers whether the player is inside it. This allows
## the interactable to become available immediately when enabled at runtime,
## without requiring the player to leave and re-enter the area.
@export var enabled: bool = true:
	set(value):
		enabled = value

		if _prompt_label:
			_prompt_label.visible = (
				enabled
				and _player_in_range
				and (
					not require_facing
					or _is_player_facing_us()
				)
			)

## If true, the player must be approximately facing the interactable.
@export var require_facing: bool = false

## Half-angle of the facing cone in degrees.
@export_range(10.0, 90.0) var facing_cone_degrees: float = 60.0


# -----------------------------------------------------------------------------
# Signals
# -----------------------------------------------------------------------------

## Emitted when the player enters interaction range.
signal focus_entered(player: Node)

## Emitted when the player leaves interaction range.
signal focus_exited(player: Node)

## Emitted when the player activates the interactable.
signal interacted(player: Node)


# -----------------------------------------------------------------------------
# Internal state
# -----------------------------------------------------------------------------

var _player: Node = null
var _player_in_range: bool = false
var _prompt_label: Label3D = null


# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

func _ready() -> void:
	if (collision_mask & 1) == 0:
		push_warning(
			"Interactable '%s': collision_mask doesn't include layer 1 "
			% name
			+ "(player). Set Mask > Layer 1 in the Inspector."
		)

	_setup_prompt_label()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _setup_prompt_label() -> void:
	# Reuse a manually configured Label3D child if one exists.
	for child in get_children():
		if child is Label3D:
			_prompt_label = child
			break

	# Otherwise, create the prompt automatically.
	if _prompt_label == null:
		_prompt_label = Label3D.new()
		_prompt_label.name = "PromptLabel"
		add_child(_prompt_label)
		_prompt_label.owner = owner

	_prompt_label.text = prompt_text
	_prompt_label.position = Vector3(0, prompt_height, 0)
	_prompt_label.font_size = prompt_font_size
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.no_depth_test = true
	_prompt_label.modulate = Color(1, 1, 1, 0.9)
	_prompt_label.visible = false


# -----------------------------------------------------------------------------
# Input
# -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not _player_in_range:
		return

	# Do not activate world interactions while dialogue is consuming input.
	var dialogue_manager: Node = get_node_or_null(
		"/root/DialogueManager"
	)

	if (
		dialogue_manager
		and dialogue_manager.has_method("is_dialogue_active")
		and dialogue_manager.is_dialogue_active()
	):
		return

	if not event.is_action_pressed(input_action):
		return

	if require_facing and not _is_player_facing_us():
		return

	if _player == null or not is_instance_valid(_player):
		push_warning(
			"Interactable '%s': player reference is invalid" % name
		)
		return

	interacted.emit(_player)
	_on_interacted(_player)


# -----------------------------------------------------------------------------
# Prompt updates
# -----------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not enabled or not _player_in_range:
		return

	if not require_facing:
		return

	if _prompt_label:
		_prompt_label.visible = _is_player_facing_us()


# -----------------------------------------------------------------------------
# Player detection
# -----------------------------------------------------------------------------

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return

	# Cache the player even while disabled. If this interactable is enabled
	# while the player remains inside it, it can respond immediately.
	_player = body
	_player_in_range = true

	if not enabled:
		return

	if _prompt_label and not require_facing:
		_prompt_label.visible = true

	focus_entered.emit(body)
	_on_focus_entered(body)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group(&"player"):
		return

	if body != _player:
		return

	_player = null
	_player_in_range = false

	if _prompt_label:
		_prompt_label.visible = false

	focus_exited.emit(body)
	_on_focus_exited(body)


# -----------------------------------------------------------------------------
# Facing
# -----------------------------------------------------------------------------

func _is_player_facing_us() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false

	var to_us: Vector3 = global_position - _player.global_position
	to_us.y = 0.0

	if to_us.length_squared() < 0.0001:
		return true

	to_us = to_us.normalized()

	# This project uses the player's movement velocity as an approximation
	# of its facing direction because the billboard sprite does not rotate.
	var player_forward: Vector3 = _player.velocity

	if player_forward.length_squared() < 0.01:
		return true

	player_forward.y = 0.0
	player_forward = player_forward.normalized()

	var threshold: float = cos(
		deg_to_rad(facing_cone_degrees)
	)

	return player_forward.dot(to_us) >= threshold


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Changes the prompt text at runtime.
func set_prompt_text(text: String) -> void:
	prompt_text = text

	if _prompt_label:
		_prompt_label.text = text


## Activates this interaction from code.
##
## This intentionally does not check `enabled`, allowing story scripts and
## cutscenes to trigger otherwise unavailable interactions when necessary.
func trigger_interaction(player: Node = null) -> void:
	var resolved_player: Node = player if player != null else _player

	if resolved_player == null:
		resolved_player = get_tree().get_first_node_in_group(&"player")

	if resolved_player == null:
		push_warning(
			"Interactable '%s': no player found" % name
		)
		return

	interacted.emit(resolved_player)
	_on_interacted(resolved_player)


# -----------------------------------------------------------------------------
# Virtual methods
# -----------------------------------------------------------------------------

## Called when the player enters interaction range.
func _on_focus_entered(_player_node: Node) -> void:
	pass


## Called when the player leaves interaction range.
func _on_focus_exited(_player_node: Node) -> void:
	pass


## Called when the player presses the interaction button while in range.
func _on_interacted(_player_node: Node) -> void:
	print("Interactable '%s' was interacted with" % name)
