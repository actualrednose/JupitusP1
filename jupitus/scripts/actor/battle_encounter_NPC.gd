extends NPC
class_name BattleEncounterNPC


@export_group("Battle")

## Battle scene loaded after this NPC's dialogue finishes.
@export_file("*.tscn") var battle_scene_path: String

## PlayerState flag set immediately before the transition begins.
@export var battle_started_flag: StringName = &"battle_started"


var _battle_starting: bool = false


func _on_interacted(_interacting_player: Node) -> void:
	if _battle_starting:
		return

	var data: DialogueData = first_dialogue

	if talked_to_before and repeat_dialogue != null:
		data = repeat_dialogue

	if data == null:
		push_warning(
			"BattleEncounterNPC '%s' has no dialogue assigned"
			% name
		)
		return

	if not DialogueManager.start_dialogue(data):
		return

	talked_to_before = true
	_battle_starting = true
	enabled = false

	await DialogueManager.dialogue_ended

	if (
		battle_scene_path.is_empty()
		or not ResourceLoader.exists(battle_scene_path)
	):
		push_error(
			"BattleEncounterNPC '%s': battle scene not found at '%s'"
			% [
				name,
				battle_scene_path
			]
		)

		_battle_starting = false
		enabled = true
		return

	if SceneManager.is_transitioning():
		push_warning(
			"BattleEncounterNPC '%s': scene transition already in progress"
			% name
		)

		_battle_starting = false
		enabled = true
		return

	PlayerState.set_flag(battle_started_flag)
	SceneManager.transition_to_scene(battle_scene_path)
