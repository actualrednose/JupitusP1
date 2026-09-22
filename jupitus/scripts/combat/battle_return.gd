extends Node
class_name BattleReturn

@export var battle_controller_path: NodePath = ^"../BattleController"
@export_file("*.tscn") var return_scene_path: String
@export var return_spawn_point: String = ""
@export var victory_flag: StringName = &"battle_won"
@export_range(0.0, 5.0, 0.1) var victory_delay: float = 1.0

var _returning: bool = false


func _ready() -> void:
	call_deferred(&"_connect_battle_result")


func _connect_battle_result() -> void:
	var controller := get_node_or_null(
		battle_controller_path
	) as BattleController

	if controller == null or controller.battle_session == null:
		push_error(
			"BattleReturn: battle_controller_path does not point to a ready "
			+ "BattleController"
		)
		return

	controller.battle_session.battle_won.connect(_on_battle_won)


func _on_battle_won() -> void:
	if _returning:
		return

	_returning = true
	PlayerState.set_flag(victory_flag)

	if victory_delay > 0.0:
		await get_tree().create_timer(victory_delay).timeout

	if return_scene_path.is_empty() or not ResourceLoader.exists(
		return_scene_path
	):
		push_error(
			"BattleReturn: return scene not found at '%s'"
			% return_scene_path
		)
		return

	SceneManager.transition_to_scene(
		return_scene_path,
		return_spawn_point
	)
