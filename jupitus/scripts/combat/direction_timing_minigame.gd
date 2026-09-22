extends Control
class_name DirectionTimingMinigame

signal correct_input()
signal completed(
	action: BattleAction,
	timing_result: BattleAction.TimingResult,
	feedback_text: String,
	successful_inputs: int
)

enum Direction {
	UP,
	RIGHT,
	DOWN,
	LEFT,
}

const DIRECTION_ACTIONS: Array[StringName] = [
	&"ui_up",
	&"ui_right",
	&"ui_down",
	&"ui_left",
]

const ALTERNATE_DIRECTION_ACTIONS: Array[StringName] = [
	&"move_up",
	&"move_right",
	&"move_down",
	&"move_left",
]

var sequence_length: int = 3
var time_limit: float = 2.25
var feedback_duration: float = 0.65
var punch_sound: AudioStream

var _action: BattleAction
var _sequence: Array[Direction] = []
var _arrows: Array[Polygon2D] = []
var _current_index: int = 0
var _correct_count: int = 0
var _time_remaining: float = 0.0
var _active: bool = false
var _accepting_input: bool = false
var _finish_id: int = 0
var _rng := RandomNumberGenerator.new()
var _panel: PanelContainer
var _prompt_label: Label
var _sequence_row: HBoxContainer
var _time_bar: ProgressBar
var _feedback_label: Label
var _audio_player: AudioStreamPlayer


func _ready() -> void:
	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_rng.randomize()
	_build_interface()


func configure(
	duration: float,
	input_count: int,
	sound: AudioStream
) -> void:
	time_limit = maxf(duration, 0.1)
	sequence_length = maxi(input_count, 1)
	punch_sound = sound


func start(
	action: BattleAction,
	input_count: int = 0
) -> void:
	if action == null:
		return

	if input_count > 0:
		sequence_length = input_count

	_finish_id += 1
	_action = action
	_current_index = 0
	_correct_count = 0
	_time_remaining = time_limit
	_active = true
	_accepting_input = true
	_feedback_label.visible = false
	_prompt_label.text = "Enter the directions!"
	_generate_sequence()
	_rebuild_arrows()
	_resize_panel_for_sequence()
	_time_bar.max_value = time_limit
	_time_bar.value = time_limit
	visible = true
	set_process(true)


func is_active() -> bool:
	return _active


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false

	if not _accepting_input:
		return true

	if event is InputEventKey:
		var key_event := event as InputEventKey

		if key_event.echo:
			return true

	for direction_index in range(
		DIRECTION_ACTIONS.size()
	):
		var primary_pressed := (
			event.is_action_pressed(
				DIRECTION_ACTIONS[direction_index]
			)
		)
		var alternate_pressed := (
			InputMap.has_action(
				ALTERNATE_DIRECTION_ACTIONS[
					direction_index
				]
			)
			and event.is_action_pressed(
				ALTERNATE_DIRECTION_ACTIONS[
					direction_index
				]
			)
		)

		if primary_pressed or alternate_pressed:
			_submit_direction(
				direction_index as Direction
			)
			return true

	return true


func _process(delta: float) -> void:
	if not _active or not _accepting_input:
		return

	_time_remaining = maxf(
		_time_remaining - delta,
		0.0
	)
	_time_bar.value = _time_remaining

	if _time_remaining <= 0.0:
		_finish_unentered_slots()
		_finish_attempt()


func _generate_sequence() -> void:
	_sequence.clear()

	for _index in range(sequence_length):
		_sequence.append(
			_rng.randi_range(
				Direction.UP,
				Direction.LEFT
			) as Direction
		)


func _rebuild_arrows() -> void:
	for child in _sequence_row.get_children():
		child.free()

	_arrows.clear()

	var slot_size := _get_arrow_slot_size()
	var polygon_scale := slot_size / 88.0
	var center := Vector2.ONE * slot_size * 0.5

	_sequence_row.add_theme_constant_override(
		"separation",
		_get_arrow_separation()
	)

	for direction in _sequence:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(
			slot_size,
			slot_size
		)
		holder.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE
		)

		var outline := Polygon2D.new()
		outline.polygon = _make_arrow_polygon(
			polygon_scale
		)
		outline.position = center
		outline.rotation = (
			float(direction) * PI * 0.5
		)
		outline.scale = Vector2(1.14, 1.14)
		outline.color = Color(
			0.02,
			0.02,
			0.03,
			0.95
		)
		holder.add_child(outline)

		var arrow := Polygon2D.new()
		arrow.polygon = _make_arrow_polygon(
			polygon_scale
		)
		arrow.position = center
		arrow.rotation = (
			float(direction) * PI * 0.5
		)
		arrow.color = Color("#E5E5E5")
		holder.add_child(arrow)

		_sequence_row.add_child(holder)
		_arrows.append(arrow)


func _resize_panel_for_sequence() -> void:
	var arrow_width := _get_arrow_slot_size()
	var separation := float(
		_get_arrow_separation()
	)
	var horizontal_margins := 32.0
	var content_width := (
		float(sequence_length) * arrow_width
		+ float(maxi(sequence_length - 1, 0))
			* separation
		+ horizontal_margins
	)
	var panel_width := maxf(
		460.0,
		content_width
	)

	_panel.custom_minimum_size = Vector2(
		panel_width,
		220.0
	)
	_panel.offset_left = -panel_width * 0.5
	_panel.offset_top = 90.0
	_panel.offset_right = panel_width * 0.5
	_panel.offset_bottom = 310.0


func _get_arrow_slot_size() -> float:
	return (
		64.0
		if sequence_length > 4
		else 88.0
	)


func _get_arrow_separation() -> int:
	return (
		12
		if sequence_length > 4
		else 18
	)


func _make_arrow_polygon(
	size_scale: float = 1.0
) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -38.0) * size_scale,
		Vector2(32.0, -6.0) * size_scale,
		Vector2(14.0, -6.0) * size_scale,
		Vector2(14.0, 34.0) * size_scale,
		Vector2(-14.0, 34.0) * size_scale,
		Vector2(-14.0, -6.0) * size_scale,
		Vector2(-32.0, -6.0) * size_scale,
	])


func _set_arrow_result(
	index: int,
	correct: bool
) -> void:
	if index < 0 or index >= _arrows.size():
		return

	var arrow := _arrows[index]
	arrow.color = (
		Color("#72F58A")
		if correct
		else Color("#FF6B6B")
	)
	arrow.scale = Vector2(1.22, 1.22)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		arrow,
		"scale",
		Vector2.ONE,
		0.14
	)


func _submit_direction(
	pressed_direction: Direction
) -> void:
	if _current_index >= _sequence.size():
		return

	var correct := (
		pressed_direction
		== _sequence[_current_index]
	)
	_set_arrow_result(
		_current_index,
		correct
	)

	if correct:
		_correct_count += 1
		_play_punch()
		correct_input.emit()

	_current_index += 1

	if _current_index >= _sequence.size():
		_finish_attempt()


func _finish_unentered_slots() -> void:
	while _current_index < _arrows.size():
		_set_arrow_result(
			_current_index,
			false
		)
		_current_index += 1


func _finish_attempt() -> void:
	if not _accepting_input:
		return

	_accepting_input = false
	set_process(false)

	var timing_result := (
		BattleAction.TimingResult.MISS
	)
	var feedback_text := "Rough combo!"
	var feedback_color := Color("#F4B65F")

	if _correct_count >= sequence_length:
		timing_result = (
			BattleAction.TimingResult.PERFECT
		)
		feedback_text = "Perfect combo!"
		feedback_color = Color("#72F58A")

	elif _correct_count >= sequence_length - 1:
		timing_result = (
			BattleAction.TimingResult.GOOD
		)
		feedback_text = "Solid combo!"
		feedback_color = Color("#B8F28A")

	elif _correct_count > 0:
		timing_result = (
			BattleAction.TimingResult.NONE
		)

	_prompt_label.text = (
		"%d/%d correct"
		% [_correct_count, sequence_length]
	)
	_feedback_label.text = feedback_text
	_feedback_label.add_theme_color_override(
		"font_color",
		feedback_color
	)
	_feedback_label.visible = true

	var finish_id := _finish_id
	await get_tree().create_timer(
		feedback_duration
	).timeout

	if finish_id != _finish_id:
		return

	var finished_action := _action
	_active = false
	_action = null
	visible = false
	completed.emit(
		finished_action,
		timing_result,
		feedback_text,
		_correct_count
	)


func _play_punch() -> void:
	if punch_sound == null:
		return

	_audio_player.stream = punch_sound
	_audio_player.play()


func _build_interface() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(
		Control.PRESET_CENTER_TOP
	)
	_panel.custom_minimum_size = Vector2(
		460.0,
		220.0
	)
	_panel.offset_left = -230.0
	_panel.offset_top = 90.0
	_panel.offset_right = 230.0
	_panel.offset_bottom = 310.0
	_panel.add_theme_stylebox_override(
		"panel",
		_make_style(
			Color(0.03, 0.04, 0.07, 0.94),
			Color("#FFD84A")
		)
	)
	add_child(_panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override(
		"separation",
		14
	)
	_panel.add_child(layout)

	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_prompt_label.add_theme_font_size_override(
		"font_size",
		24
	)
	layout.add_child(_prompt_label)

	_sequence_row = HBoxContainer.new()
	_sequence_row.alignment = (
		BoxContainer.ALIGNMENT_CENTER
	)
	_sequence_row.add_theme_constant_override(
		"separation",
		18
	)
	layout.add_child(_sequence_row)

	_time_bar = ProgressBar.new()
	_time_bar.custom_minimum_size = Vector2(
		0.0,
		18.0
	)
	_time_bar.show_percentage = false
	layout.add_child(_time_bar)

	_feedback_label = Label.new()
	_feedback_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_feedback_label.add_theme_font_size_override(
		"font_size",
		28
	)
	_feedback_label.add_theme_constant_override(
		"outline_size",
		7
	)
	_feedback_label.add_theme_color_override(
		"font_outline_color",
		Color(
			0.02,
			0.02,
			0.02,
			0.95
		)
	)
	_feedback_label.visible = false
	layout.add_child(_feedback_label)

	_audio_player = AudioStreamPlayer.new()
	add_child(_audio_player)


func _make_style(
	background: Color,
	border: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	return style
