# cutscene_player.gd
# -----------------------------------------------------------------------------
# Attach to: Node placed anywhere in the scene.
#
# Plays a sequence of CutsceneAction resources, freezes the player, restores
# the camera afterward, and supports skipping.
# -----------------------------------------------------------------------------

extends Node
class_name CutscenePlayer


signal cutscene_started()
signal cutscene_finished()
signal cutscene_skipped()


@export_group("Cutscene")

## Actions executed sequentially by this cutscene.
@export var actions: Array[CutsceneAction] = []

## Whether the player should remain frozen throughout the cutscene.
@export var freeze_player: bool = true


@export_group("Skipping")

## Whether the player can skip this cutscene.
@export var can_skip: bool = true

## Input action used to skip.
@export var skip_input_action: StringName = &"ui_cancel"


var _is_playing: bool = false
var _is_skipping: bool = false
var _current_action_index: int = -1


## Starts the cutscene.
func play() -> bool:
	if _is_playing:
		push_warning(
			"CutscenePlayer: play() called but cutscene is already playing"
		)
		return false

	if actions.is_empty():
		push_warning("CutscenePlayer: no actions to play")
		return false

	if DialogueManager.is_dialogue_active():
		push_warning(
			"CutscenePlayer: cannot start cutscene while dialogue is active"
		)
		return false

	_is_playing = true
	_is_skipping = false
	_current_action_index = -1

	cutscene_started.emit()

	if freeze_player:
		_set_player_frozen(true)

	_current_action_index = 0

	while _current_action_index < actions.size():
		if _is_skipping:
			break

		var action: CutsceneAction = actions[_current_action_index]

		if action != null:
			# The base CutsceneAction method is synchronous, but subclasses can
			# override it with coroutine behavior. The await must remain here.
			@warning_ignore("redundant_await")
			await action.execute(self)

		# DialogueManager releases its own freeze when dialogue ends. Reassert
		# the enclosing cutscene's freeze before running subsequent actions.
		if freeze_player and not _is_skipping:
			_set_player_frozen(true)

		_current_action_index += 1

	_cleanup_after_cutscene()
	return true


## Requests that the current cutscene be skipped.
func skip() -> void:
	if not _is_playing or not can_skip:
		return

	if _is_skipping:
		return

	_is_skipping = true
	cutscene_skipped.emit()

	if (
		_current_action_index >= 0
		and _current_action_index < actions.size()
	):
		var action: CutsceneAction = actions[_current_action_index]

		if action != null:
			action.skip(self)


## Returns whether the cutscene is currently playing.
func is_playing() -> bool:
	return _is_playing


func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing or not can_skip:
		return

	if event.is_action_pressed(skip_input_action):
		skip()
		get_viewport().set_input_as_handled()


func _cleanup_after_cutscene() -> void:
	var was_skipped := _is_skipping

	var camera: Camera3D = get_viewport().get_camera_3d()

	if camera and "target" in camera:
		var player: Node = get_tree().get_first_node_in_group(&"player")

		if player:
			camera.target = player

	if freeze_player:
		_set_player_frozen(false)

	_is_playing = false
	_is_skipping = false
	_current_action_index = -1

	# cutscene_skipped is emitted when the skip is requested. Only emit
	# cutscene_finished when every action completed naturally.
	if not was_skipped:
		cutscene_finished.emit()


func _set_player_frozen(value: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group(&"player")

	if (
		player
		and is_instance_valid(player)
		and player.has_method("set_frozen")
	):
		player.set_frozen(value)
