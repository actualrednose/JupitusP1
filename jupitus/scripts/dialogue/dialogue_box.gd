# dialogue_box.gd
# -----------------------------------------------------------------------------
# Attach to: the root Control of dialogue_box.tscn
#
# What this script does:
#   - Displays a dialogue box at the bottom of the screen
#   - Types out text character-by-character (typewriter effect)
#   - Plays a sound blip per character (Animal Crossing style)
#   - Shows a name plate and portrait for the speaking character
#   - Handles choice selection (numbered list, arrow keys + E)
#   - Tween-eases the box in/out of view
#   - Emits signals when the line is fully displayed and when the
#     player advances
#
# Expected node structure (see dialogue_box.tscn setup instructions):
#   DialogueBox (Control, full rect)            ← this script
#   ├── Dimmer (ColorRect, full rect, black, alpha 0)
#   ├── PortraitContainer (HBoxContainer)
#   │   ├── PortraitParty1 (TextureRect)        ← party member 1 (far left)
#   │   ├── PortraitParty2 (TextureRect)        ← party member 2 (left-center)
#   │   ├── PortraitNpc1 (TextureRect)          ← NPC 1 (right-center)
#   │   └── PortraitNpc2 (TextureRect)          ← NPC 2 (far right)
#   ├── Box (Panel, anchored bottom-center)
#   │   ├── NamePlate (Panel)
#   │   │   └── NameLabel (Label)
#   │   ├── TextLabel (RichTextLabel)
#   │   ├── ContinuePrompt (Label or TextureRect)
#   │   └── ChoiceList (VBoxContainer)
#   │       └── (ChoiceButton children spawned at runtime)
#
# Visual novel style with party/NPC split:
#   - Party members (DialogueCharacter.is_party_member = true) → LEFT side
#   - NPCs (is_party_member = false) → RIGHT side
#   - Active speaker's portrait is full brightness; others are dimmed
#   - Brightness transitions are tweened for smooth visual feel
#   - Narration lines dim all portraits equally
#   - Up to 2 party members + 2 NPCs visible simultaneously (4 slots total)
# -----------------------------------------------------------------------------

extends Control
class_name DialogueBox

# --- Signals ---

# Emitted when the typewriter finishes revealing all text on a line.
# Useful for triggering animations, sounds, or camera moves on specific beats.
signal line_complete(line: DialogueLine)

# Emitted when the player advances past a line (presses E after line_complete).
# The line_index is the 0-based index of the line that was just advanced past.
signal line_advanced(line_index: int)

# Emitted when the player picks a choice. Passes the chosen choice and
# its index in the choices array.
signal choice_made(choice: DialogueChoice, index: int)

# Emitted when the entire conversation ends (last line advanced, or
# a choice with next_line_id pointing past the end is picked).
signal conversation_ended()

# --- Tweakable values ---

@export_group("Typewriter")
## Characters per second. 30 = natural read, 60 = fast, 15 = dramatic.
@export_range(5.0, 200.0) var chars_per_second: float = 40.0

## Sound effect played per character during typewriter. Should be very short
## (under 100ms) and quiet — it plays many times per second.
## Use a .wav or .ogg file. Mono is fine.
##
## Leave null to disable blips entirely (text just types silently).
@export var blip_sound: AudioStream = null

## Pitch variation applied to each blip. Randomized per character so the
## sound doesn't get monotonous. 1.0 = no variation, 0.1 = ±10% pitch.
@export_range(0.0, 0.5) var blip_pitch_variation: float = 0.05

## How often (in characters) to play a blip. 1 = every char (chatty),
## 2 = every other char, 3 = every third (sparser, more naturalistic).
@export_range(1, 5) var blip_every_n_chars: int = 2

## If true, blip sound pitch is per-character (each character has a base pitch,
## varied slightly per char). If false, all characters use the same pitch.
## (Future feature — for now we just use the global pitch with variation.)
@export var per_character_pitch: bool = false

@export_group("Input")
## Which input action advances the dialogue. Defaults to "interact" (E).
@export var advance_action: StringName = &"interact"

## Which input actions navigate choices (up/down).
@export var choice_up_action: StringName = &"move_up"
@export var choice_down_action: StringName = &"move_down"

@export_group("Visuals")
## How long (seconds) the box takes to tween in/out.
@export var box_tween_duration: float = 0.2

## How dark the dimmer gets when dialogue is active. 0.0 = invisible,
## 0.5 = half-darkened, 0.7 = strong dim. 0.4-0.5 is the sweet spot —
## dims the world but doesn't feel like night.
@export_range(0.0, 1.0) var dimmer_max_alpha: float = 0.4

## How long (seconds) the dimmer takes to fade in/out. Usually slightly
## slower than the box for a more graceful feel.
@export var dimmer_tween_duration: float = 0.3

## How long (seconds) portrait brightness transitions take when the
## active speaker changes. 0 = instant (snappy), 0.2 = smooth fade.
## 0.15 is the visual novel standard — fast enough to not feel laggy,
## slow enough to be noticed.
@export var portrait_tween_duration: float = 0.15

## Modulate color for "dimmed" (non-active) portraits. Default is a
## dark grey at 40% brightness. Tweak if you want dimmed characters
## to be more or less visible.
@export var dimmed_portrait_color: Color = Color(0.4, 0.4, 0.4, 1)

@export_group("Colors")
## Color of the dimmer overlay. Black is standard. Tinting it slightly
## blue/purple can give a more "cinematic" feel.
@export var dimmer_color: Color = Color.BLACK

# --- Internal state ---

# The current DialogueData being played.
var _data: DialogueData = null

# Current 0-based line index.
var _current_line_index: int = 0

# The DialogueLine currently being displayed.
var _current_line: DialogueLine = null

# Whether the typewriter is still revealing text (true) or done (false).
var _typing: bool = false

# Whether the dialogue box is currently visible and active.
var _active: bool = false

# Whether choices are currently being shown (and awaiting selection).
var _showing_choices: bool = false

# Currently highlighted choice index (0-based).
var _selected_choice: int = 0

# Tween for the typewriter effect. Stored so we can kill it early if the
# player presses E to skip the typewriter.
var _typewriter_tween: Tween = null

# Tween for box entry/exit.
var _box_tween: Tween = null

# Tween for dimmer fade.
var _dimmer_tween: Tween = null

# AudioStreamPlayer for blip sounds.
var _blip_player: AudioStreamPlayer = null

# --- Node references (assigned in _ready via @onready) ---

# Using @onready with $NodePath to cache references. $ is shorthand for get_node().
# % is "unique name access" — if a node has its "Access as Unique Name" toggle
# on in the editor, you can reference it as %NodeName from anywhere in the scene.
# We use % here so the script doesn't break if you restructure the tree.
@onready var _dimmer: ColorRect = %Dimmer
@onready var _box: Panel = %Box
@onready var _name_plate: Panel = %NamePlate
@onready var _name_label: Label = %NameLabel

# Portrait slots: 4 total, split between party (left) and NPCs (right).
# Layout:  [Party1] [Party2]   [Npc1] [Npc2]
#              left side         right side
#
# Slot indices:
#   0 = PortraitParty1 (far left)       — 1st party member introduced
#   1 = PortraitParty2 (left-center)    — 2nd party member introduced
#   2 = PortraitNpc1 (right-center)     — 1st NPC introduced
#   3 = PortraitNpc2 (far right)        — 2nd NPC introduced
#
# The active speaker is shown at full brightness in their assigned slot;
# other visible characters are dimmed. Empty slots are invisible.
@onready var _portrait_slots: Dictionary = {
		0: %PortraitParty1,
		1: %PortraitParty2,
		2: %PortraitNpc1,
		3: %PortraitNpc2,
}

# --- Multi-portrait state ---

# Maps each character resource (DialogueCharacter) to their slot index.
# This is populated as characters speak during a conversation.
# Example: { char_alex_id: 0, char_jamie_id: 1, char_shopkeeper_id: 2 }
var _character_slots: Dictionary = {}

# The currently speaking character. Their slot is shown at full brightness.
var _current_speaker: DialogueCharacter = null

@onready var _text_label: RichTextLabel = %TextLabel
@onready var _continue_prompt: Control = %ContinuePrompt
@onready var _choice_list: VBoxContainer = %ChoiceList


# -----------------------------------------------------------------------------
# _ready
# -----------------------------------------------------------------------------

func _ready() -> void:
		# Start invisible. We tween in when start() is called.
		_box.modulate.a = 0.0
		_dimmer.color = dimmer_color
		_dimmer.modulate.a = 0.0

		# Hide individual elements until we have content
		_continue_prompt.visible = false
		_choice_list.visible = false

		# Hide all portrait slots at start (they get shown as characters speak)
		for slot in _portrait_slots.values():
				if slot:
						slot.visible = false

		# Set up the audio player for blips
		_blip_player = AudioStreamPlayer.new()
		_blip_player.name = "BlipPlayer"
		add_child(_blip_player)
		if blip_sound:
				_blip_player.stream = blip_sound
				# Lower the volume slightly — blips play many times per second
				# and quickly become annoying at full volume.
				_blip_player.volume_db = -6.0

		# Set up mouse filter so the dialogue box doesn't block clicks we
		# don't care about. Control.MOUSE_FILTER_IGNORE means this Control
		# doesn't capture mouse events at all (we use keyboard input).
		mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Process mode: ALWAYS so we still receive input even if the game is
		# paused (e.g., during cutscenes where time is stopped).
		process_mode = Node.PROCESS_MODE_ALWAYS


# -----------------------------------------------------------------------------
# _unhandled_input
# -----------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
		# Only respond to input when the dialogue box is active.
		if not _active:
				return

		# If we're showing choices, navigation takes priority.
		if _showing_choices:
				if _handle_choice_input(event):
						# Input was consumed — mark it as handled so other nodes
						# (like Interactables) don't also receive it.
						get_viewport().set_input_as_handled()
				return

		# Otherwise, the advance_action handles:
		#   - If still typing: snap to full text (skip typewriter)
		#   - If line is complete: advance to next line (or end conversation)
		if event.is_action_pressed(advance_action):
				_advance_or_skip()
				# CRITICAL: mark the input as handled so other nodes don't receive it.
				# Without this, the Interactable that triggered the dialogue would
				# ALSO receive the same E press and try to start a new conversation,
				# causing the "dialogue already active" warning AND immediately
				# restarting dialogue when it ends.
				#
				# set_input_as_handled() tells Godot "I consumed this event, don't
				# pass it to other _unhandled_input handlers in this frame."
				get_viewport().set_input_as_handled()


# -----------------------------------------------------------------------------
# Public API (called by DialogueManager)
# -----------------------------------------------------------------------------

## Start showing a new conversation. Tweens the box in, then plays the first line.
func start_dialogue(data: DialogueData) -> void:
		_data = data
		_current_line_index = 0
		_active = true
		_showing_choices = false

		# Reset multi-portrait state for the new conversation
		_character_slots.clear()
		_current_speaker = null
		for slot in _portrait_slots.values():
				if slot:
						slot.visible = false
						slot.texture = null

		# Show the box (tween alpha from 0 to 1)
		_show_box(true)
		_show_dimmer(true)

		# Wait for the box tween to finish before starting the first line,
		# so the typewriter doesn't start while the box is still sliding in.
		#
		# `await` pauses this function until the signal fires. We create a
		# one-shot timer since we don't have direct access to the tween's
		# finished signal here (tween kills/restarts would complicate things).
		await get_tree().create_timer(box_tween_duration).timeout

		_play_current_line()


## End the conversation. Tweens the box out and emits conversation_ended.
func end_dialogue() -> void:
		_active = false
		_showing_choices = false

		# Kill any in-progress typewriter
		_kill_typewriter()

		# Show the box/dimmer going away
		_show_box(false)
		_show_dimmer(false)

		# Hide and clear all portrait slots so they don't linger on screen
		# after the conversation ends. This also kills any in-progress
		# brightness tweens that might otherwise try to update slots after
		# we've cleared their textures.
		for slot in _portrait_slots.values():
				if slot:
						# Kill any active brightness tween on this slot
						if slot.has_meta("brightness_tween"):
								var existing_tween: Tween = slot.get_meta("brightness_tween")
								if existing_tween and existing_tween.is_valid():
										existing_tween.kill()
						slot.visible = false
						slot.texture = null
						slot.modulate = dimmed_portrait_color  # reset to dimmed for next time

		conversation_ended.emit()

		# Clear references so we don't accidentally reuse stale state
		_data = null
		_current_line = null
		_current_line_index = 0
		_current_speaker = null
		_character_slots.clear()


## Returns true if dialogue is currently active.
func is_active() -> bool:
		return _active


# -----------------------------------------------------------------------------
# Internal: line playback
# -----------------------------------------------------------------------------

func _play_current_line() -> void:
		if _data == null:
				push_warning("DialogueBox: _play_current_line called but _data is null")
				return

		# Get the line at the current index.
		# If the index is out of range, the conversation is over.
		if _current_line_index >= _data.lines.size():
				end_dialogue()
				return

		_current_line = _data.lines[_current_line_index]

		# Update the UI for this line
		_update_speaker_ui(_current_line)
		_update_text_ui(_current_line)

		# Hide choices if they were visible (from a previous line)
		_hide_choices()
		_continue_prompt.visible = false

		# Start the typewriter
		_start_typewriter(_current_line.text)


func _advance_or_skip() -> void:
		if _typing:
				# Typewriter is still going — skip to full text
				_kill_typewriter()
				_text_label.visible_characters = -1  # -1 = show all
				_typing = false
				_on_typewriter_finished()
		else:
				# Line is fully displayed — advance
				_advance_line()


func _advance_line() -> void:
		line_advanced.emit(_current_line_index)

		# If this line has choices, show them and wait for selection.
		# _advance_line is only called when the player presses E to advance,
		# so if we have choices we display them now.
		if _current_line.has_choices():
				_show_choices(_current_line.choices)
				return

		# Otherwise, advance to the next line based on next_line_id:
		# - next_line_id <= 0: go to next line in array (linear)
		# - next_line_id > 0: jump to that 1-based line index
		var next_index: int
		if _current_line.next_line_id > 0:
				# next_line_id is 1-based; convert to 0-based array index
				next_index = _current_line.next_line_id - 1
		else:
				next_index = _current_line_index + 1

		_current_line_index = next_index

		# Play the next line (this handles "is index out of range? end conversation")
		_play_current_line()


# -----------------------------------------------------------------------------
# Internal: speaker UI (visual-novel style multi-portrait)
# -----------------------------------------------------------------------------

func _update_speaker_ui(line: DialogueLine) -> void:
		if line.is_narration():
				# Narration: hide the name plate. Don't change portraits — the
				# characters stay visible (dimmed) while narration plays, which
				# is the visual novel convention.
				_name_plate.visible = false
				# Dim all portraits equally during narration (no "active" speaker)
				_set_all_portraits_dimmed()
				return

		# Show name plate with the character's display name
		_name_plate.visible = true
		_name_label.text = line.speaker.display_name

		# Apply the character's name color (if non-default)
		if line.speaker.name_color != Color.WHITE:
				_name_label.add_theme_color_override("font_color", line.speaker.name_color)
		else:
				# Remove the override so it uses the theme default
				_name_label.remove_theme_color_override("font_color")

		# Assign this speaker a slot if they don't have one yet.
		# First speaker gets center (slot 1), second gets left (slot 0),
		# third gets right (slot 2). This ordering puts the "main" speaker
		# in center, the second-most-important on the left, and a third
		# character on the right.
		#
		# We use the resource's instance ID as the dictionary key so two
		# different resources with the same display_name still get distinct slots.
		var speaker_id: int = line.speaker.get_instance_id()
		if not _character_slots.has(speaker_id):
				_assign_slot(line.speaker, speaker_id)

		# Update which slot is the "active" (full brightness) one
		_current_speaker = line.speaker
		_update_portrait_brightness()


# -----------------------------------------------------------------------------
# Internal: slot management
# -----------------------------------------------------------------------------

## Assign a portrait slot to a character who hasn't appeared yet.
## Slot assignment is based on whether the character is a party member:
##
##   Party members (is_party_member = true):
##     1st party member → slot 0 (far left)
##     2nd party member → slot 1 (left-center)
##
##   NPCs (is_party_member = false):
##     1st NPC → slot 2 (right-center)
##     2nd NPC → slot 3 (far right)
##
##   3rd+ party member or 3rd+ NPC → no slot (just name in nameplate)
##
## If you want different behavior (e.g., a specific slot per character
## regardless of introduction order), override this method in a subclass.
func _assign_slot(character: DialogueCharacter, speaker_id: int) -> void:
		var slot_index: int = -1

		if character.is_party_member:
				# Count how many party members are already assigned
				var party_count: int = 0
				for slot in _character_slots.values():
						if slot == 0 or slot == 1:
								party_count += 1

				# Assign next available party slot (0 or 1)
				match party_count:
						0:
								slot_index = 0  # far left
						1:
								slot_index = 1  # left-center
						_:
								slot_index = -1  # no slot available
		else:
				# NPC: count how many NPCs are already assigned
				var npc_count: int = 0
				for slot in _character_slots.values():
						if slot == 2 or slot == 3:
								npc_count += 1

				# Assign next available NPC slot (2 or 3)
				match npc_count:
						0:
								slot_index = 2  # right-center
						1:
								slot_index = 3  # far right
						_:
								slot_index = -1  # no slot available

		_character_slots[speaker_id] = slot_index

		# If we got a valid slot, populate it with the character's default portrait
		if slot_index >= 0 and _portrait_slots.has(slot_index):
				var slot: TextureRect = _portrait_slots[slot_index]
				if slot:
						slot.texture = character.get_portrait("")
						slot.visible = true


## Update the brightness of all portrait slots based on _current_speaker.
## The active speaker's slot tweens to full brightness; all others tween
## to dimmed. We use tweens for the smooth visual-novel-style transition.
func _update_portrait_brightness() -> void:
		if _current_speaker == null:
				_set_all_portraits_dimmed()
				return

		var active_id: int = _current_speaker.get_instance_id()
		var active_slot: int = _character_slots.get(active_id, -1)

		for slot_index in _portrait_slots.keys():
				var slot: TextureRect = _portrait_slots[slot_index]
				if slot == null or not slot.visible:
						continue

				var target_color: Color
				if slot_index == active_slot:
						# Active speaker: full brightness
						target_color = Color.WHITE
				else:
						# Other characters: dimmed
						target_color = dimmed_portrait_color

				# Tween the modulate color smoothly. We create one tween per slot
				# so each portrait transitions independently. The tween is killed
				# before creating a new one, so rapid speaker changes don't accumulate.
				#
				# Using create_tween() with set_trans and set_ease for a nice
				# ease-in-out feel.
				if portrait_tween_duration <= 0.0:
						# Duration 0 = instant (no tween) — useful for tests or if
						# the tween causes issues
						slot.modulate = target_color
				else:
						# Kill any existing tween on this slot. We use a metadata key
						# on the slot itself to track the active tween.
						#
						# We check has_meta() before calling get_meta() because
						# get_meta() with a default arg still logs an error in
						# Godot 4 when the meta doesn't exist (even though it
						# returns the default). has_meta() is the safe way.
						if slot.has_meta("brightness_tween"):
								var existing_tween: Tween = slot.get_meta("brightness_tween")
								if existing_tween and existing_tween.is_valid():
										existing_tween.kill()

						var tween: Tween = create_tween()
						tween.tween_property(slot, "modulate", target_color, portrait_tween_duration)
						tween.set_trans(Tween.TRANS_SINE)
						tween.set_ease(Tween.EASE_IN_OUT)
						slot.set_meta("brightness_tween", tween)


## Dim all visible portraits equally (used during narration lines).
## Also uses tweens for smooth transitions.
func _set_all_portraits_dimmed() -> void:
		for slot in _portrait_slots.values():
				if slot and slot.visible:
						if portrait_tween_duration <= 0.0:
								slot.modulate = dimmed_portrait_color
						else:
								if slot.has_meta("brightness_tween"):
										var existing_tween: Tween = slot.get_meta("brightness_tween")
										if existing_tween and existing_tween.is_valid():
												existing_tween.kill()
								var tween: Tween = create_tween()
								tween.tween_property(slot, "modulate", dimmed_portrait_color, portrait_tween_duration)
								tween.set_trans(Tween.TRANS_SINE)
								tween.set_ease(Tween.EASE_IN_OUT)
								slot.set_meta("brightness_tween", tween)


# -----------------------------------------------------------------------------
# Internal: text UI (typewriter)
# -----------------------------------------------------------------------------

func _update_text_ui(line: DialogueLine) -> void:
		# RichTextLabel: set the full text, then control visibility per-character
		# via the visible_characters property.
		#   visible_characters = 0   → nothing visible
		#   visible_characters = 5   → first 5 chars visible
		#   visible_characters = -1  → all visible
		_text_label.text = line.text
		_text_label.visible_characters = 0


func _start_typewriter(text: String) -> void:
		_kill_typewriter()  # safety: kill any existing tween

		# Create a new tween. Tweens are the Godot 4 way to animate properties.
		# We bind it to `self` so it auto-frees if the dialogue box is destroyed.
		_typewriter_tween = create_tween()

		# Animate visible_characters from 0 to text.length() over a duration
		# based on chars_per_second. We use Tween.tween_method because
		# visible_characters is a property that needs a method call to update
		# (it's an int, and we want to interpolate it smoothly).
		#
		# Actually, visible_characters IS a property, so we can use tween_property.
		# However, it's an int — tweens interpolate floats, so we round-trip.
		# The cleanest approach is tween_method with a setter.
		var duration: float = text.length() / float(chars_per_second)
		_typewriter_tween.tween_method(_set_visible_chars, 0, text.length(), duration)
		_typewriter_tween.tween_callback(_on_typewriter_finished)

		_typing = true

		# Reset blip counter so the first character blips immediately
		_blip_counter = 0


# This is the setter called by the tween. It receives a float, rounds it
# to an int, and assigns it to visible_characters.
func _set_visible_chars(count: float) -> void:
		var int_count: int = int(round(count))
		_text_label.visible_characters = int_count

		# Play blip sound if a new character was just revealed
		_try_play_blip(int_count)


# Counter for "every N chars" blip logic.
var _blip_counter: int = 0

func _try_play_blip(current_chars: int) -> void:
		if blip_sound == null or _blip_player == null:
				return

		# If we just revealed a new character (count increased), maybe play blip
		# We compare to _blip_counter to know how many NEW chars appeared this frame.
		# (At high chars_per_second, multiple chars might appear per frame.)
		while _blip_counter < current_chars:
				# Only play a blip every Nth character (e.g., every 2nd char)
				if _blip_counter % blip_every_n_chars == 0:
						_play_blip()
				_blip_counter += 1


func _play_blip() -> void:
		if _blip_player == null or _blip_player.stream == null:
				return
		# Randomize pitch slightly for naturalistic variation
		var base_pitch: float = 1.0
		var pitch: float = base_pitch + randf_range(-blip_pitch_variation, blip_pitch_variation)
		_blip_player.pitch_scale = max(0.5, pitch)  # clamp to avoid extreme values
		_blip_player.play()


func _kill_typewriter() -> void:
		if _typewriter_tween != null:
				_typewriter_tween.kill()
				_typewriter_tween = null
		_typing = false


func _on_typewriter_finished() -> void:
		_typing = false

		# Show the "press E to continue" prompt (unless choices are about to show)
		if _current_line and not _current_line.has_choices():
				_continue_prompt.visible = true

		line_complete.emit(_current_line)


# -----------------------------------------------------------------------------
# Internal: choices
# -----------------------------------------------------------------------------

func _show_choices(choices: Array[DialogueChoice]) -> void:
		_showing_choices = true
		_selected_choice = 0

		# Clear any existing choice buttons
		for child in _choice_list.get_children():
				child.queue_free()

		# Create a button for each choice
		for i in range(choices.size()):
				var choice: DialogueChoice = choices[i]
				var button: Button = Button.new()
				# Format: "1. Choice text"
				button.text = "%d. %s" % [i + 1, choice.text]
				# Make the button non-interactive (we handle input ourselves via keyboard)
				# This way the button is purely visual — clicking it does nothing,
				# only keyboard navigation works.
				button.disabled = true
				button.focus_mode = Control.FOCUS_NONE
				_choice_list.add_child(button)

		_choice_list.visible = true
		_update_choice_highlight()


func _hide_choices() -> void:
		_showing_choices = false
		_choice_list.visible = false
		for child in _choice_list.get_children():
				child.queue_free()


func _update_choice_highlight() -> void:
		# Highlight the currently selected choice by tinting its background
		for i in range(_choice_list.get_child_count()):
				var button: Button = _choice_list.get_child(i)
				if i == _selected_choice:
						# Selected: brighter
						button.add_theme_color_override("font_color", Color.YELLOW)
						button.add_theme_stylebox_override("disabled",
								_make_highlight_stylebox())
				else:
						# Not selected: default
						button.remove_theme_color_override("font_color")
						button.remove_theme_stylebox_override("disabled")


func _make_highlight_stylebox() -> StyleBox:
		# Create a simple highlight stylebox (semi-transparent yellow background)
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 0, 0.2)
		sb.border_color = Color.YELLOW
		sb.border_width_left = 2
		sb.border_width_right = 2
		sb.border_width_top = 2
		sb.border_width_bottom = 2
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		return sb


func _handle_choice_input(event: InputEvent) -> bool:
		# Returns true if we consumed the input, false otherwise.
		# This lets the caller decide whether to mark the input as handled.
		if event.is_action_pressed(choice_up_action):
				_selected_choice = (_selected_choice - 1) % _current_line.choices.size()
				if _selected_choice < 0:
						_selected_choice = _current_line.choices.size() - 1
				_update_choice_highlight()
				return true
		elif event.is_action_pressed(choice_down_action):
				_selected_choice = (_selected_choice + 1) % _current_line.choices.size()
				_update_choice_highlight()
				return true
		elif event.is_action_pressed(advance_action):
				_confirm_choice()
				return true
		return false


func _confirm_choice() -> void:
		var choice: DialogueChoice = _current_line.choices[_selected_choice]
		choice_made.emit(choice, _selected_choice)

		# Set the flag if specified
		if not choice.sets_flag.is_empty():
				# DialogueManager is the singleton that owns the flags dict
				DialogueManager.flags[choice.sets_flag] = true

		_hide_choices()

		# Determine where to go next
		var next_index: int
		if choice.next_line_id > 0:
				next_index = choice.next_line_id - 1
		else:
				next_index = _current_line_index + 1

		_current_line_index = next_index
		_play_current_line()


# -----------------------------------------------------------------------------
# Internal: box & dimmer tweening
# -----------------------------------------------------------------------------

func _show_box(make_visible: bool) -> void:
		# Kill any existing tween so they don't fight
		if _box_tween:
				_box_tween.kill()
		_box_tween = create_tween()
		var target_alpha: float = 1.0 if make_visible else 0.0
		_box_tween.tween_property(_box, "modulate:a", target_alpha, box_tween_duration)


func _show_dimmer(make_visible: bool) -> void:
		if _dimmer_tween:
				_dimmer_tween.kill()
		_dimmer_tween = create_tween()
		var target_alpha: float = dimmer_max_alpha if make_visible else 0.0
		_dimmer_tween.tween_property(_dimmer, "modulate:a", target_alpha, dimmer_tween_duration)


# -----------------------------------------------------------------------------
# Future extensions (notes for later)
# -----------------------------------------------------------------------------
#
# 1. PER-CHARACTER BLIP PITCH
#    Each DialogueCharacter could have a `blip_pitch: float` property.
#    When that character is speaking, the dialogue box uses their pitch
#    as the base for blip variation. High-pitched characters sound
#    different from low-pitched ones.
#
# 2. SHAKE / EMPHASIS TAGS
#    Support inline tags in text like "[shake]WHAT?![/shake]" to add
#    visual emphasis. RichTextLabel supports custom BBCODE, so we'd
#    need to enable bbcode_enabled and write a small parser.
#
# 3. AUTO-ADVANCE
#    A `auto_advance_delay: float` per line. If > 0, the line advances
#    automatically after that many seconds (no E press needed). Useful
#    for cutscenes where you want tight pacing control.
#
# 4. CONTINUE PROMPT ANIMATION
#    The "press E" prompt could pulse (scale up/down) to draw attention.
#    Implementation: a Tween that loops.
