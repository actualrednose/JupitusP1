extends Node3D

@export_group("Scene Nodes")
@export var intro_trigger_path: NodePath = ^"RobberyCutscene/Area3D"
@export var post_battle_cutscene_path: NodePath = ^"PostBattleCutscene"
@export var cultist_path: NodePath = ^"MachineCultist"
@export var clerk_path: NodePath = ^"KogelBotClerk"
@export var milk_path: NodePath = ^"MilkInteractable"

@export_group("Story Flags")
@export var cultist_defeated_flag: StringName = &"machine_cultist_defeated"
@export var robbery_in_progress_flag: StringName = &"robbery_in_progress"
@export var robbery_finished_flag: StringName = &"robbery_finished"
@export var battle_started_flag: StringName = &"machine_cultist_battle_started"

@onready var _intro_trigger := get_node_or_null(
	intro_trigger_path
) as CutsceneTrigger

@onready var _post_battle_cutscene := get_node_or_null(
	post_battle_cutscene_path
) as CutscenePlayer

@onready var _cultist := get_node_or_null(cultist_path) as NPC
@onready var _clerk := get_node_or_null(clerk_path) as NPC
@onready var _milk := get_node_or_null(milk_path) as MilkInteractable

var _post_battle_started: bool = false


func _ready() -> void:
	if not _validate_scene_nodes():
		return

	if PlayerState.has_flag(robbery_finished_flag):
		_apply_completed_state()
		return

	_clerk.enabled = false

	if not PlayerState.has_flag(cultist_defeated_flag):
		return

	_prepare_post_battle_state()

	if SceneManager.is_transitioning():
		SceneManager.transition_finished.connect(
			_start_post_battle_cutscene,
			CONNECT_ONE_SHOT
		)
	else:
		_start_post_battle_cutscene.call_deferred()


func _validate_scene_nodes() -> bool:
	var valid := true

	if _intro_trigger == null:
		push_error("KogelMartProgression: intro trigger not found")
		valid = false

	if _post_battle_cutscene == null:
		push_error("KogelMartProgression: post-battle cutscene not found")
		valid = false

	if _cultist == null:
		push_error("KogelMartProgression: MachineCultist not found")
		valid = false

	if _clerk == null:
		push_error("KogelMartProgression: KogelBotClerk not found")
		valid = false

	if _milk == null:
		push_error("KogelMartProgression: MilkInteractable not found")
		valid = false

	return valid


func _prepare_post_battle_state() -> void:
	_intro_trigger.enabled = false
	_cultist.enabled = false
	_clerk.enabled = false
	_milk.enabled = false


func _start_post_battle_cutscene() -> void:
	if _post_battle_started:
		return

	_post_battle_started = true

	_post_battle_cutscene.cutscene_finished.connect(
		_on_post_battle_cutscene_finished,
		CONNECT_ONE_SHOT
	)

	_post_battle_cutscene.play()


func _on_post_battle_cutscene_finished() -> void:
	PlayerState.set_flag(robbery_in_progress_flag, false)
	PlayerState.set_flag(robbery_finished_flag)
	PlayerState.set_flag(battle_started_flag, false)

	_apply_completed_state()


func _apply_completed_state() -> void:
	_intro_trigger.enabled = false

	_cultist.enabled = false
	_cultist.visible = false

	_clerk.enabled = true
	_milk.enabled = true
