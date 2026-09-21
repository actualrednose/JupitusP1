extends HBoxContainer
class_name BattlePartyCard

const ICON_OUTLINE_SHADER := """
shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(1.0, 0.847, 0.29, 1.0);
uniform float outline_width : hint_range(1.0, 4.0) = 3.0;

void fragment() {
	vec2 padding = outline_width * TEXTURE_PIXEL_SIZE;
	vec2 icon_uv = (UV - padding) / (vec2(1.0) - padding * 2.0);
	vec4 source = vec4(0.0);

	if (
		icon_uv.x >= 0.0
		&& icon_uv.x <= 1.0
		&& icon_uv.y >= 0.0
		&& icon_uv.y <= 1.0
	) {
		source = texture(TEXTURE, icon_uv);
	}

	if (!outline_enabled) {
		COLOR = source;
	} else {
		float nearby_alpha = 0.0;

		for (int x = -4; x <= 4; x++) {
			for (int y = -4; y <= 4; y++) {
				vec2 offset = vec2(float(x), float(y));

				if (length(offset) <= outline_width) {
					vec2 sample_uv = (
						icon_uv
						+ offset * TEXTURE_PIXEL_SIZE
					);

					if (
						sample_uv.x >= 0.0
						&& sample_uv.x <= 1.0
						&& sample_uv.y >= 0.0
						&& sample_uv.y <= 1.0
					) {
						nearby_alpha = max(
							nearby_alpha,
							texture(
								TEXTURE,
								sample_uv
							).a
						);
					}
				}
			}
		}

		float outline_alpha = nearby_alpha * (1.0 - source.a);
		vec3 final_color = mix(outline_color.rgb, source.rgb, source.a);
		float final_alpha = max(source.a, outline_alpha * outline_color.a);
		COLOR = vec4(final_color, final_alpha);
	}
}
"""

signal clicked(combatant: CombatantState)

var combatant: CombatantState

var _icon_holder: PanelContainer
var _icon_feedback: Control
var _icon: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_trail_bar: ProgressBar
var _hp_value_label: Label
var _tempo_bar: ProgressBar
var _tempo_value_label: Label
var _state_label: Label
var _feedback := BattleActorView.new()
var _built: bool = false
var _value_tweens: Array[Tween] = []
var _idle_sway_tween: Tween
var _icon_outline_material: ShaderMaterial
var _selected_action: BattleAction


func _ready() -> void:
	_ensure_built()


func bind_combatant(value: CombatantState) -> void:
	combatant = value
	_ensure_built()

	if combatant == null:
		return

	_icon.texture = combatant.definition.icon
	_name_label.text = combatant.definition.display_name
	_configure_bars()
	sync_from_state()


func set_active(value: bool) -> void:
	if not _built:
		return

	_icon_outline_material.set_shader_parameter(
		"outline_enabled",
		value
	)


func set_selected_action(action: BattleAction) -> void:
	_selected_action = action
	_refresh_state_label()


func get_presentation_position() -> Vector2:
	return _feedback.get_presentation_position()


func play_anticipation(
	_duration: float,
	reduced_motion: bool
) -> void:
	_set_idle_sway_enabled(not reduced_motion)


func play_attack(
	_target_position: Vector2,
	_duration: float,
	reduced_motion: bool
) -> void:
	_set_idle_sway_enabled(not reduced_motion)


func play_hit(
	direction: Vector2,
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_hit(
		direction,
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_guard(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_guard(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_heal(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_heal(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_interrupt(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_interrupt(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_power_charge(
	duration: float,
	reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	_feedback.play_power_charge(
		duration,
		reduced_motion,
		reduced_flashing
	)


func play_defeat(
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_defeat(duration, reduced_motion)


func play_recovery(
	duration: float,
	reduced_motion: bool
) -> void:
	_feedback.play_recovery(duration, reduced_motion)


func show_damage_number(
	amount: int,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(
		str(amount),
		Color("#FF6B6B"),
		reduced_motion
	)


func show_healing_number(
	amount: int,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(
		"+%d" % amount,
		Color("#72F58A"),
		reduced_motion
	)


func show_tempo_change(
	amount: int,
	reduced_motion: bool = false
) -> void:
	var prefix := "+" if amount >= 0 else ""
	_feedback.show_number(
		"%s%d TEMPO" % [prefix, amount],
		Color("#F4B65F"),
		reduced_motion
	)


func show_result_text(
	text: String,
	color: Color,
	reduced_motion: bool = false
) -> void:
	_feedback.show_number(text, color, reduced_motion)


func animate_result(
	result: BattleEffectResult,
	duration: float
) -> void:
	if result == null:
		return

	_stop_value_tweens()

	if result.hp_after != result.hp_before:
		_hp_value_label.text = "%d/%d" % [
			result.hp_after,
			combatant.definition.max_hp
		]

		var hp_tween := create_tween()
		_value_tweens.append(hp_tween)
		hp_tween.tween_property(
			_hp_bar,
			"value",
			result.hp_after,
			duration * 0.45
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		if result.hp_after < result.hp_before:
			hp_tween.tween_interval(duration * 0.2)
			hp_tween.tween_property(
				_hp_trail_bar,
				"value",
				result.hp_after,
				duration * 0.35
			).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_hp_trail_bar.value = result.hp_after

	if result.tempo_after != result.tempo_before:
		_tempo_value_label.text = "%d/%d" % [
			result.tempo_after,
			combatant.definition.max_tempo
		]
		var tempo_tween := create_tween()
		_value_tweens.append(tempo_tween)
		tempo_tween.tween_property(
			_tempo_bar,
			"value",
			result.tempo_after,
			duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		if _became_skill_ready(
			result.tempo_before,
			result.tempo_after
		):
			show_result_text(
				"SKILL READY!",
				Color("#FFD166")
			)


func pulse_tempo(
	_amount: int,
	duration: float,
	_reduced_motion: bool,
	reduced_flashing: bool
) -> void:
	if reduced_flashing:
		return

	var tween := create_tween()
	_value_tweens.append(tween)
	tween.tween_property(
		_tempo_bar,
		"modulate",
		Color("#FFF2A8"),
		duration * 0.35
	)
	tween.tween_property(
		_tempo_bar,
		"modulate",
		Color.WHITE,
		duration * 0.65
	)


func sync_from_state() -> void:
	if combatant == null or not _built:
		return

	_feedback.skip_and_reset()
	_stop_value_tweens()
	_hp_bar.value = combatant.current_hp
	_hp_trail_bar.value = combatant.current_hp
	_hp_value_label.text = "%d/%d" % [
		combatant.current_hp,
		combatant.definition.max_hp
	]
	_tempo_bar.value = combatant.current_tempo
	_tempo_value_label.text = "%d/%d" % [
		combatant.current_tempo,
		combatant.definition.max_tempo
	]

	if combatant.is_defeated():
		_icon_feedback.modulate = Color(
			0.45,
			0.45,
			0.45,
			1.0
		)
	else:
		_icon_feedback.modulate = Color.WHITE

	_refresh_state_label()
	_feedback.recapture_base_modulate()


func skip_presentation() -> void:
	_feedback.skip_and_reset()
	_stop_value_tweens()


func _ensure_built() -> void:
	if _built:
		return

	_built = true
	custom_minimum_size = Vector2(300.0, 120.0)
	add_theme_constant_override("separation", 12)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)

	_icon_holder = PanelContainer.new()
	_icon_holder.custom_minimum_size = Vector2(96.0, 96.0)
	_icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.add_theme_stylebox_override(
		"panel",
		StyleBoxEmpty.new()
	)
	add_child(_icon_holder)

	_icon_feedback = Control.new()
	_icon_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_holder.add_child(_icon_feedback)
	_icon_feedback.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_icon_feedback.pivot_offset = Vector2(48.0, 48.0)

	_icon = TextureRect.new()
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_feedback.add_child(_icon)
	_icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.pivot_offset = Vector2(48.0, 48.0)
	_icon_outline_material = _make_icon_outline_material()
	_icon.material = _icon_outline_material

	var stats := VBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.custom_minimum_size = Vector2(190.0, 0.0)
	stats.add_theme_constant_override("separation", 4)
	add_child(stats)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override(
		"font_color",
		Color("#202020")
	)
	stats.add_child(_name_label)

	var hp_row := _make_hp_row()
	stats.add_child(hp_row)

	var tempo_row := _make_tempo_row()
	stats.add_child(tempo_row)

	_state_label = Label.new()
	_state_label.visible = false
	stats.add_child(_state_label)

	_feedback.setup(
		self,
		_icon_feedback,
		_icon_feedback,
		Vector2(24.0, -8.0)
	)
	_start_idle_sway()


func _make_hp_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = "HP:"
	label.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(label)

	var bars := Control.new()
	bars.custom_minimum_size = Vector2(150.0, 20.0)
	row.add_child(bars)

	_hp_trail_bar = _make_bar(
		Color("#F0B14E"),
		Color("#D8D8D8")
	)
	bars.add_child(_hp_trail_bar)

	_hp_bar = _make_bar(
		Color("#62D84E"),
		Color(0.0, 0.0, 0.0, 0.0)
	)
	bars.add_child(_hp_bar)

	_hp_value_label = Label.new()
	_hp_value_label.custom_minimum_size = Vector2(65.0, 0.0)
	row.add_child(_hp_value_label)
	return row


func _make_tempo_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = "TEMPO:"
	label.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(label)

	_tempo_bar = _make_bar(
		Color("#E5A24E"),
		Color("#D8D8D8")
	)
	_tempo_bar.custom_minimum_size = Vector2(150.0, 20.0)
	row.add_child(_tempo_bar)

	_tempo_value_label = Label.new()
	_tempo_value_label.custom_minimum_size = Vector2(65.0, 0.0)
	row.add_child(_tempo_value_label)
	return row


func _make_bar(
	fill_color: Color,
	background_color: Color
) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.show_percentage = false
	bar.add_theme_stylebox_override(
		"background",
		_make_bar_style(background_color)
	)
	bar.add_theme_stylebox_override(
		"fill",
		_make_bar_style(fill_color)
	)
	return bar


func _make_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _make_icon_outline_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = ICON_OUTLINE_SHADER

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter(
		"outline_color",
		Color("#FFD84A")
	)
	material.set_shader_parameter(
		"outline_width",
		3.0
	)
	material.set_shader_parameter(
		"outline_enabled",
		false
	)
	return material


func _configure_bars() -> void:
	_hp_bar.max_value = combatant.definition.max_hp
	_hp_trail_bar.max_value = combatant.definition.max_hp
	_tempo_bar.max_value = combatant.definition.max_tempo


func _became_skill_ready(
	tempo_before: int,
	tempo_after: int
) -> bool:
	for skill in combatant.definition.skills:
		if (
			skill != null
			and tempo_before < skill.tempo_cost
			and tempo_after >= skill.tempo_cost
		):
			return true

	return false


func _stop_value_tweens() -> void:
	for tween in _value_tweens:
		if tween != null and tween.is_valid():
			tween.kill()

	_value_tweens.clear()


func _start_idle_sway() -> void:
	if (
		_idle_sway_tween != null
		and _idle_sway_tween.is_valid()
	):
		_idle_sway_tween.play()
		return

	_idle_sway_tween = _icon.create_tween()
	_idle_sway_tween.set_loops()
	_idle_sway_tween.set_trans(Tween.TRANS_SINE)
	_idle_sway_tween.set_ease(Tween.EASE_IN_OUT)

	_idle_sway_tween.tween_property(
		_icon,
		"rotation_degrees",
		-3.0,
		0.9
	)

	_idle_sway_tween.tween_property(
		_icon,
		"rotation_degrees",
		3.0,
		1.8
	)

	_idle_sway_tween.tween_property(
		_icon,
		"rotation_degrees",
		0.0,
		0.9
	)


func _set_idle_sway_enabled(value: bool) -> void:
	if value:
		_start_idle_sway()
		return

	if (
		_idle_sway_tween != null
		and _idle_sway_tween.is_valid()
	):
		_idle_sway_tween.pause()

	_icon.rotation_degrees = 0.0


func _refresh_state_label() -> void:
	if combatant == null:
		return

	if combatant.is_defeated():
		_state_label.text = "DEFEATED"
		_state_label.visible = true
	elif combatant.is_guarding:
		_state_label.text = "GUARDING"
		_state_label.visible = true
	elif _selected_action != null:
		_state_label.text = (
			"READY: %s"
			% _selected_action.ability.display_name
		)
		_state_label.visible = true
	else:
		_state_label.text = ""
		_state_label.visible = false


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
		):
			clicked.emit(combatant)
			accept_event()
