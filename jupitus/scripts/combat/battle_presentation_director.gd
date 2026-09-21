extends Node
class_name BattlePresentationDirector

signal action_presentation_started(action: BattleAction)
signal effect_presentation_started(result: BattleEffectResult)
signal action_presentation_finished(action: BattleAction)
signal presentation_skipped(action: BattleAction)

@export_group("Timing")
## Overall presentation speed. Values above 1 make every stage faster.
@export_range(0.25, 4.0, 0.05) var animation_speed: float = 1.0

## Time spent telegraphing an ordinary action before it moves toward its target.
@export_range(0.0, 2.0, 0.01) var anticipation_duration: float = 0.18

## Additional anticipation for a power attack.
@export_range(0.0, 2.0, 0.01) var power_attack_pause: float = 0.22

## Time used for an attacker lunge or projectile travel.
@export_range(0.0, 2.0, 0.01) var travel_duration: float = 0.14

## Brief pause at contact before the target reacts.
@export_range(0.0, 0.25, 0.01) var hit_stop_duration: float = 0.08

## Time used for hit, heal, guard, and interrupt reactions.
@export_range(0.0, 2.0, 0.01) var result_duration: float = 0.28

## Time used for the attacker to return to its resting pose.
@export_range(0.0, 2.0, 0.01) var recovery_duration: float = 0.16

## Multiplier applied while the player holds the fast-forward input.
@export_range(1.0, 10.0, 0.25) var fast_forward_multiplier: float = 3.0

@export_group("Accessibility")
## Disables lunges, recoil, floating-number movement, and camera shake.
@export var reduced_motion: bool = false

## Disables bright hit, heal, guard, and interrupt flashes.
@export var reduced_flashing: bool = false

## Strength of the small directional shake applied to the assigned stage.
@export_range(0.0, 30.0, 0.5) var camera_shake_strength: float = 5.0

## Optional Node2D containing the battle actors. Leave empty to disable shake.
@export var shake_target: Node2D

@export_group("Optional Audio")
## Played when damage lands.
@export var hit_sound: AudioStream

## Optional second impact layer played with the main hit sound.
@export var hit_accent_sound: AudioStream

## Played when HP is restored.
@export var heal_sound: AudioStream

## Played when guard is applied.
@export var guard_sound: AudioStream

## Played when a prepared power attack is disrupted.
@export var interrupt_sound: AudioStream

## Played during the extended anticipation of a power attack.
@export var power_attack_charge_sound: AudioStream

## Disables all presentation audio without changing assigned resources.
@export var mute_audio: bool = false

var _session: BattleSession
var _views: Dictionary = {}
var _presenting: bool = false
var _fast_forwarding: bool = false
var _presentation_id: int = 0
var _current_action: BattleAction
var _shake_base_position: Vector2
var _shake_tween: Tween
var _effect_audio: AudioStreamPlayer
var _accent_audio: AudioStreamPlayer
var _charge_audio: AudioStreamPlayer


func _ready() -> void:
	_effect_audio = AudioStreamPlayer.new()
	_effect_audio.name = "EffectAudio"
	add_child(_effect_audio)

	_accent_audio = AudioStreamPlayer.new()
	_accent_audio.name = "AccentAudio"
	add_child(_accent_audio)

	_charge_audio = AudioStreamPlayer.new()
	_charge_audio.name = "ChargeAudio"
	add_child(_charge_audio)

	if shake_target != null:
		_shake_base_position = shake_target.position


func setup(session: BattleSession) -> void:
	if _session == session:
		return

	if (
		_session != null
		and _session.action_resolved.is_connected(
			_on_action_resolved
		)
	):
		_session.action_resolved.disconnect(
			_on_action_resolved
		)

	_session = session

	if (
		_session != null
		and not _session.action_resolved.is_connected(
			_on_action_resolved
		)
	):
		_session.action_resolved.connect(
			_on_action_resolved
		)


func register_view(
	combatant: CombatantState,
	view: Object
) -> void:
	if combatant == null or view == null:
		return

	_views[combatant] = view


func unregister_view(
	combatant: CombatantState
) -> void:
	_views.erase(combatant)


func set_fast_forwarding(value: bool) -> void:
	_fast_forwarding = value


func is_presenting() -> bool:
	return _presenting


func present_power_attack_charge(
	combatant: CombatantState
) -> void:
	var view: Object = _views.get(combatant)

	_call_view(
		view,
		"play_power_charge",
		[
			_scaled_tween_duration(0.45),
			reduced_motion,
			reduced_flashing
		]
	)

	_play_audio(
		power_attack_charge_sound,
		_charge_audio
	)


func skip_current_presentation() -> void:
	if not _presenting:
		return

	var skipped_action := _current_action

	_presentation_id += 1
	_presenting = false
	_current_action = null

	_stop_all_view_animation()
	_stop_shake()
	_sync_all_views()

	presentation_skipped.emit(skipped_action)
	call_deferred("_continue_resolution")


func _on_action_resolved(
	action: BattleAction
) -> void:
	if action == null:
		call_deferred("_continue_resolution")
		return

	_presentation_id += 1
	_presenting = true
	_current_action = action

	_present_action.call_deferred(
		action,
		_presentation_id
	)


func _present_action(
	action: BattleAction,
	presentation_id: int
) -> void:
	await get_tree().process_frame

	if not _is_current(presentation_id):
		return

	action_presentation_started.emit(action)

	var actor_view: Object = _views.get(action.actor)
	var target_view: Object = _find_target_view(action)
	var target_position := _get_view_position(target_view)
	var anticipation := anticipation_duration

	if (
		action.ability != null
		and action.ability.is_power_attack
	):
		anticipation += power_attack_pause

	_call_view(
		actor_view,
		"play_anticipation",
		[
			_scaled_tween_duration(anticipation),
			reduced_motion
		]
	)

	if not await _wait(
		anticipation,
		presentation_id
	):
		return

	_call_view(
		actor_view,
		"play_attack",
		[
			target_position,
			_scaled_tween_duration(
				travel_duration
			),
			reduced_motion
		]
	)

	if not await _wait(
		travel_duration,
		presentation_id
	):
		return

	for result in action.effect_results:
		if not await _present_effect(
			result,
			actor_view,
			presentation_id
		):
			return

	_call_view(
		actor_view,
		"play_recovery",
		[
			_scaled_tween_duration(
				recovery_duration
			),
			reduced_motion
		]
	)

	if not await _wait(
		recovery_duration,
		presentation_id
	):
		return

	_finish_presentation(
		action,
		presentation_id
	)


func _present_effect(
	result: BattleEffectResult,
	actor_view: Object,
	presentation_id: int
) -> bool:
	if result == null:
		return true

	effect_presentation_started.emit(result)

	var target_view: Object = _views.get(
		result.target
	)

	if result.skipped or result.missed:
		var result_text := (
			"MISS"
			if result.missed
			else "NO EFFECT"
		)

		_call_view(
			target_view,
			"show_result_text",
			[
				result_text,
				Color("#E5E5E5"),
				reduced_motion
			]
		)

		return await _wait(
			result_duration,
			presentation_id
		)

	if not result.applied:
		_call_view(
			target_view,
			"show_result_text",
			[
				"NO EFFECT",
				Color("#E5E5E5"),
				reduced_motion
			]
		)

		return await _wait(
			result_duration,
			presentation_id
		)

	match result.effect.effect_type:
		AbilityEffectDefinition.EffectType.DAMAGE:
			if not await _wait(
				hit_stop_duration,
				presentation_id
			):
				return false

			var direction := (
				_get_view_position(target_view)
				- _get_view_position(actor_view)
			)

			_call_view(
				target_view,
				"play_hit",
				[
					direction,
					_scaled_tween_duration(
						result_duration
					),
					reduced_motion,
					reduced_flashing
				]
			)

			_call_view(
				target_view,
				"show_damage_number",
				[
					result.amount,
					reduced_motion
				]
			)

			_call_view(
				target_view,
				"animate_result",
				[
					result,
					_scaled_tween_duration(
						result_duration
					)
				]
			)

			_play_audio(
				hit_sound,
				_effect_audio
			)

			_play_audio(
				hit_accent_sound,
				_accent_audio
			)

			_play_shake(
				direction,
				result.amount
			)

		AbilityEffectDefinition.EffectType.HEAL, AbilityEffectDefinition.EffectType.REVIVE:
			_call_view(
				target_view,
				"play_heal",
				[
					_scaled_tween_duration(
						result_duration
					),
					reduced_motion,
					reduced_flashing
				]
			)

			_call_view(
				target_view,
				"show_healing_number",
				[
					result.amount,
					reduced_motion
				]
			)

			_call_view(
				target_view,
				"animate_result",
				[
					result,
					_scaled_tween_duration(
						result_duration
					)
				]
			)

			_play_audio(
				heal_sound,
				_effect_audio
			)

		AbilityEffectDefinition.EffectType.TEMPO:
			_call_view(
				target_view,
				"show_tempo_change",
				[
					result.amount,
					reduced_motion
				]
			)

			_call_view(
				target_view,
				"animate_result",
				[
					result,
					_scaled_tween_duration(
						result_duration
					)
				]
			)

		AbilityEffectDefinition.EffectType.GUARD:
			_call_view(
				target_view,
				"play_guard",
				[
					_scaled_tween_duration(
						result_duration
					),
					reduced_motion,
					reduced_flashing
				]
			)

			_play_audio(
				guard_sound,
				_effect_audio
			)

		AbilityEffectDefinition.EffectType.STAGGER:
			if result.disrupted:
				_call_view(
					target_view,
					"play_interrupt",
					[
						_scaled_tween_duration(
							result_duration
						),
						reduced_motion,
						reduced_flashing
					]
				)

				_call_view(
					target_view,
					"show_result_text",
					[
						"BREAK!",
						Color("#FFF29A"),
						reduced_motion
					]
				)

				_play_audio(
					interrupt_sound,
					_effect_audio
				)

		AbilityEffectDefinition.EffectType.APPLY_STATUS:
			var status_name := "STATUS"

			if result.effect.status != null:
				status_name = (
					result.effect.status.display_name
				)

			_call_view(
				target_view,
				"show_result_text",
				[
					status_name.to_upper(),
					Color("#D9A7FF"),
					reduced_motion
				]
			)

		AbilityEffectDefinition.EffectType.CLEANSE:
			_call_view(
				target_view,
				"show_result_text",
				[
					"CLEANSED",
					Color("#A8F0FF"),
					reduced_motion
				]
			)

		_:
			_call_view(
				target_view,
				"animate_result",
				[
					result,
					_scaled_tween_duration(
						result_duration
					)
				]
			)

	if result.tempo_after != result.tempo_before:
		_call_view(
			target_view,
			"pulse_tempo",
			[
				(
					result.tempo_after
					- result.tempo_before
				),
				_scaled_tween_duration(
					result_duration
				),
				reduced_motion,
				reduced_flashing
			]
		)

	if not await _wait(
		result_duration,
		presentation_id
	):
		return false

	if result.defeated:
		_call_view(
			target_view,
			"play_defeat",
			[
				_scaled_tween_duration(
					result_duration
				),
				reduced_motion
			]
		)

		if not await _wait(
			result_duration,
			presentation_id
		):
			return false

	return true


func _finish_presentation(
	action: BattleAction,
	presentation_id: int
) -> void:
	if not _is_current(presentation_id):
		return

	_presenting = false
	_current_action = null

	_stop_shake()
	_sync_all_views()

	action_presentation_finished.emit(action)
	call_deferred("_continue_resolution")


func _continue_resolution() -> void:
	if _session != null:
		_session.continue_resolution()


func _wait(
	duration: float,
	presentation_id: int
) -> bool:
	var remaining := maxf(duration, 0.0)

	while remaining > 0.0:
		await get_tree().process_frame

		if not _is_current(presentation_id):
			return false

		var multiplier := animation_speed

		if _fast_forwarding:
			multiplier *= fast_forward_multiplier

		remaining -= (
			get_process_delta_time()
			* multiplier
		)

	return _is_current(presentation_id)


func _is_current(
	presentation_id: int
) -> bool:
	return (
		_presenting
		and presentation_id == _presentation_id
	)


func _find_target_view(
	action: BattleAction
) -> Object:
	if (
		action.target != null
		and _views.has(action.target)
	):
		return _views[action.target]

	for result in action.effect_results:
		if (
			result != null
			and _views.has(result.target)
		):
			return _views[result.target]

	return null


func _get_view_position(
	view: Object
) -> Vector2:
	if (
		view != null
		and view.has_method(
			"get_presentation_position"
		)
	):
		return view.call(
			"get_presentation_position"
		) as Vector2

	return Vector2.ZERO


func _call_view(
	view: Object,
	method: StringName,
	arguments: Array
) -> void:
	if view != null and view.has_method(method):
		view.callv(method, arguments)


func _sync_all_views() -> void:
	for view: Object in _views.values():
		_call_view(
			view,
			&"sync_from_state",
			[]
		)


func _stop_all_view_animation() -> void:
	for view: Object in _views.values():
		_call_view(
			view,
			&"skip_presentation",
			[]
		)


func _play_shake(
	direction: Vector2,
	amount: int
) -> void:
	if (
		shake_target == null
		or reduced_motion
		or camera_shake_strength <= 0.0
	):
		return

	_stop_shake()

	var strength := minf(
		camera_shake_strength
			+ float(amount) * 0.08,
		camera_shake_strength * 2.0
	)

	var shake_direction := -direction.normalized()

	if shake_direction == Vector2.ZERO:
		shake_direction = Vector2.RIGHT

	_shake_tween = create_tween()

	for multiplier in [
		1.0,
		-0.65,
		0.35,
		0.0
	]:
		_shake_tween.tween_property(
			shake_target,
			"position",
			(
				_shake_base_position
				+ shake_direction
				* strength
				* multiplier
			),
			_scaled_tween_duration(0.025)
		)


func _stop_shake() -> void:
	if (
		_shake_tween != null
		and _shake_tween.is_valid()
	):
		_shake_tween.kill()

	_shake_tween = null

	if shake_target != null:
		shake_target.position = (
			_shake_base_position
		)


func _play_audio(
	stream: AudioStream,
	player: AudioStreamPlayer
) -> void:
	if stream == null or player == null:
		return

	if mute_audio:
		return

	player.stream = stream
	player.play()


func _scaled_tween_duration(
	duration: float
) -> float:
	var multiplier := animation_speed

	if _fast_forwarding:
		multiplier *= fast_forward_multiplier

	return duration / maxf(multiplier, 0.01)
