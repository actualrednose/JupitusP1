extends Control
class_name CrosshairTimingMinigame

signal completed(
	action: BattleAction,
	timing_result: BattleAction.TimingResult,
	feedback_text: String
)

var crosshair_texture: Texture2D
var input_action: StringName = &"interact"
var travel_speed: float = 500.0
var killshot_radius: float = 24.0
var clean_shot_radius: float = 72.0
var edge_padding: float = 48.0
var crosshair_size: Vector2 = Vector2(72.0, 72.0)
var feedback_duration: float = 0.65

var _action: BattleAction
var _target_position: Vector2
var _crosshair_x: float = 0.0
var _right_edge: float = 0.0
var _active: bool = false
var _accepting_input: bool = false
var _finish_id: int = 0
var _guide_line: ColorRect
var _crosshair_holder: Control
var _crosshair_image: TextureRect
var _fallback_crosshair: Control
var _feedback_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	_build_interface()


func configure(
	texture: Texture2D,
	confirm_action: StringName,
	speed: float,
	perfect_radius: float,
	good_radius: float
) -> void:
	crosshair_texture = texture
	input_action = confirm_action
	travel_speed = maxf(speed, 1.0)
	killshot_radius = maxf(perfect_radius, 1.0)
	clean_shot_radius = maxf(
		good_radius,
		killshot_radius
	)

	if crosshair_texture == null:
		push_warning(
			"CrosshairTimingMinigame: no crosshair texture assigned; using the temporary fallback"
		)

	_refresh_crosshair_visual()


func start(
	action: BattleAction,
	target_position: Vector2
) -> void:
	if action == null:
		return

	_finish_id += 1
	_action = action
	_target_position = target_position
	_target_position.x = clampf(
		_target_position.x,
		edge_padding,
		size.x - edge_padding
	)
	_target_position.y = clampf(
		_target_position.y,
		crosshair_size.y * 0.5,
		size.y - crosshair_size.y * 0.5
	)

	_crosshair_x = edge_padding
	_right_edge = maxf(
		size.x - edge_padding,
		_crosshair_x
	)
	_active = true
	_accepting_input = true
	_feedback_label.visible = false
	_guide_line.visible = true
	visible = true
	set_process(true)
	_update_positions()


func is_active() -> bool:
	return _active


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false

	var pressed := event.is_action_pressed(
		input_action
	)

	if event.is_action_pressed("ui_accept"):
		pressed = true

	if event is InputEventMouseButton:
		var mouse_event := (
			event as InputEventMouseButton
		)
		pressed = (
			mouse_event.button_index
				== MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		)

	if event is InputEventKey:
		var key_event := event as InputEventKey

		if key_event.echo:
			pressed = false

	if pressed and _accepting_input:
		_finish_attempt()

	return true


func _process(delta: float) -> void:
	if not _active or not _accepting_input:
		return

	_crosshair_x += travel_speed * delta

	if _crosshair_x >= _right_edge:
		_crosshair_x = _right_edge
		_update_positions()
		_finish_attempt()
		return

	_update_positions()


func _build_interface() -> void:
	_guide_line = ColorRect.new()
	_guide_line.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_guide_line.color = Color(
		1.0,
		0.85,
		0.3,
		0.28
	)
	add_child(_guide_line)

	_crosshair_holder = Control.new()
	_crosshair_holder.custom_minimum_size = (
		crosshair_size
	)
	_crosshair_holder.size = crosshair_size
	_crosshair_holder.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	add_child(_crosshair_holder)

	_crosshair_image = TextureRect.new()
	_crosshair_image.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_crosshair_image.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)
	_crosshair_image.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_crosshair_image.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	_crosshair_image.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_crosshair_holder.add_child(
		_crosshair_image
	)

	_fallback_crosshair = Control.new()
	_fallback_crosshair.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_fallback_crosshair.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_crosshair_holder.add_child(
		_fallback_crosshair
	)
	_build_fallback_crosshair()

	_feedback_label = Label.new()
	_feedback_label.custom_minimum_size = Vector2(
		280.0,
		54.0
	)
	_feedback_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_feedback_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_feedback_label.add_theme_font_size_override(
		"font_size",
		30
	)
	_feedback_label.add_theme_constant_override(
		"outline_size",
		8
	)
	_feedback_label.add_theme_color_override(
		"font_outline_color",
		Color(0.05, 0.05, 0.05, 0.9)
	)
	_feedback_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_feedback_label.visible = false
	add_child(_feedback_label)
	_refresh_crosshair_visual()


func _build_fallback_crosshair() -> void:
	var horizontal := ColorRect.new()
	horizontal.color = Color("#FFD84A")
	horizontal.position = Vector2(
		4.0,
		crosshair_size.y * 0.5 - 2.0
	)
	horizontal.size = Vector2(
		crosshair_size.x - 8.0,
		4.0
	)
	horizontal.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_fallback_crosshair.add_child(horizontal)

	var vertical := ColorRect.new()
	vertical.color = Color("#FFD84A")
	vertical.position = Vector2(
		crosshair_size.x * 0.5 - 2.0,
		4.0
	)
	vertical.size = Vector2(
		4.0,
		crosshair_size.y - 8.0
	)
	vertical.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_fallback_crosshair.add_child(vertical)

	var center := ColorRect.new()
	center.color = Color.WHITE
	center.position = Vector2(
		crosshair_size.x * 0.5 - 4.0,
		crosshair_size.y * 0.5 - 4.0
	)
	center.size = Vector2(8.0, 8.0)
	center.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_fallback_crosshair.add_child(center)


func _refresh_crosshair_visual() -> void:
	if _crosshair_image == null:
		return

	_crosshair_image.texture = crosshair_texture
	_crosshair_image.visible = (
		crosshair_texture != null
	)
	_fallback_crosshair.visible = (
		crosshair_texture == null
	)


func _update_positions() -> void:
	_guide_line.position = Vector2(
		edge_padding,
		_target_position.y - 1.0
	)
	_guide_line.size = Vector2(
		maxf(
			size.x - edge_padding * 2.0,
			0.0
		),
		2.0
	)
	_crosshair_holder.position = Vector2(
		_crosshair_x - crosshair_size.x * 0.5,
		_target_position.y - crosshair_size.y * 0.5
	)
	_feedback_label.position = Vector2(
		_target_position.x
			- _feedback_label.custom_minimum_size.x
			* 0.5,
		_target_position.y
			- crosshair_size.y
			- _feedback_label.custom_minimum_size.y
	)


func _finish_attempt() -> void:
	if not _accepting_input:
		return

	_accepting_input = false
	set_process(false)
	_guide_line.visible = false

	var distance := absf(
		_crosshair_x - _target_position.x
	)
	var timing_result := BattleAction.TimingResult.NONE
	var feedback_text := "Glancing shot!"
	var feedback_color := Color("#F4B65F")

	if distance <= killshot_radius:
		timing_result = (
			BattleAction.TimingResult.PERFECT
		)
		feedback_text = "Killshot!"
		feedback_color = Color("#FFD84A")
	elif distance <= clean_shot_radius:
		timing_result = (
			BattleAction.TimingResult.GOOD
		)
		feedback_text = "Clean shot!"
		feedback_color = Color("#B8F28A")

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
		feedback_text
	)
