# dialogue_manager.gd
# -----------------------------------------------------------------------------
# This is an Autoload (singleton) — there's only ever one instance of it,
# accessible from anywhere via `DialogueManager`.
#
# What this script does:
#   - Holds the global dialogue box instance
#   - Provides start_dialogue() / end_dialogue() / is_dialogue_active()
#   - Maintains a flags dictionary for branching state
#   - Freezes the player while dialogue is active
#   - Manages the dialogue box lifecycle
# -----------------------------------------------------------------------------

extends Node

signal dialogue_started(data: DialogueData)
signal dialogue_ended()

# Flags set by dialogue choices and completed conversations.
var flags: Dictionary = {}

var _dialogue_box: DialogueBox = null
var _active: bool = false
var _active_data: DialogueData = null
var _player: Node = null


func start_dialogue(data: DialogueData) -> bool:
	if data == null:
		push_warning(
			"DialogueManager: start_dialogue called with null data"
		)
		return false

	if not data.requires_flag.is_empty():
		if not flags.get(data.requires_flag, false):
			return false

	if _active:
		push_warning(
			"DialogueManager: start_dialogue called but a dialogue is already active"
		)
		return false

	_ensure_dialogue_box()

	if _dialogue_box == null:
		return false

	_player = get_tree().get_first_node_in_group(
		&"player"
	)

	if (
		_player != null
		and _player.has_method("set_frozen")
	):
		_player.set_frozen(true)

	_active_data = data
	_active = true
	dialogue_started.emit(data)

	_dialogue_box.start_dialogue.call_deferred(
		data
	)

	if not _dialogue_box.conversation_ended.is_connected(
		_on_conversation_ended
	):
		_dialogue_box.conversation_ended.connect(
			_on_conversation_ended,
			CONNECT_ONE_SHOT
		)

	return true


func end_dialogue() -> void:
	if _dialogue_box != null:
		_dialogue_box.end_dialogue()


func is_dialogue_active() -> bool:
	return _active


func clear_flags() -> void:
	flags.clear()


func _ensure_dialogue_box() -> void:
	if (
		_dialogue_box != null
		and is_instance_valid(_dialogue_box)
	):
		return

	var box_scene: PackedScene = load(
		"res://scenes/ui/dialogue_box.tscn"
	)

	if box_scene == null:
		push_error(
			"DialogueManager: couldn't load "
			+ "res://scenes/ui/dialogue_box.tscn"
		)
		return

	_dialogue_box = box_scene.instantiate()
	get_tree().root.add_child(_dialogue_box)

	_dialogue_box.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)


func _on_conversation_ended() -> void:
	var completed_data := _active_data
	_active_data = null

	if (
		completed_data != null
		and not completed_data
			.sets_flag_on_complete
			.is_empty()
	):
		flags[
			completed_data.sets_flag_on_complete
		] = true

	if (
		_player != null
		and is_instance_valid(_player)
		and _player.has_method("set_frozen")
	):
		_player.set_frozen(false)

	_player = null
	_active = false
	dialogue_ended.emit()
