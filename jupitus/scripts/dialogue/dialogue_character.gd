# dialogue_character.gd
# -----------------------------------------------------------------------------
# A Resource that defines a character who can participate in dialogue.
# Each character has a display name and an optional default portrait.
#
# Why a Resource instead of just strings?
#   - Single source of truth: change "Bob" to "Robert" in one place and
#     every dialogue line referencing that character updates.
#   - Inspector-friendly: you author characters as .tres files in the editor,
#     drag them into dialogue lines, no typos possible.
#   - Extensible: later we can add voice bank, text color, name box style,
#     etc. to this resource without rewriting dialogue lines.
#
# Usage:
#   1. In the FileSystem, right-click res://resources/dialogue/ → New Resource
#   2. Pick "DialogueCharacter" from the list
#   3. Save as e.g. "char_alex.tres"
#   4. In the Inspector, set Display Name and drag in a portrait texture
#   5. Reference this .tres file from DialogueLine resources
# -----------------------------------------------------------------------------

extends Resource
class_name DialogueCharacter

# --- Character properties ---

## The name shown in the dialogue box's name plate (top of the box).
## Keep it short — long names will overflow the name plate at small UI sizes.
@export var display_name: String = "Unknown"

## If true, this character is a party member (player-controlled protagonist
## or someone traveling with them). Party members are shown on the LEFT side
## of the dialogue box; NPCs are shown on the RIGHT side.
##
## Set this to true for Alex, Jamie, and any other party members.
## Leave it false for shopkeepers, enemies, quest givers, etc.
@export var is_party_member: bool = false

## Default portrait texture shown when this character is speaking.
## Should be a square texture (e.g., 96x96 or 128x128). The dialogue box
## will resize it to fit the portrait frame.
##
## If null, the dialogue box will show a placeholder rectangle. Useful
## during early development when you don't have art yet.
@export var portrait: Texture2D = null

## Optional text color for this character's name plate. If set, the dialogue
## box will tint the name plate background or text to match. Leave as
## default (white) if you don't want per-character coloring.
@export var name_color: Color = Color.WHITE

## Optional alternate portraits (e.g., happy, sad, angry variants).
## These are accessed by name from DialogueLine.portrait_override.
## Format: keys are short identifiers like "happy", "sad", "angry".
##
## Example usage in DialogueLine:
##   portrait_override = "happy"
## → the dialogue box looks up "happy" in this dictionary and uses that
##   texture instead of the default portrait.
##
## If portrait_override doesn't match any key, the default `portrait`
## above is used as a fallback.
@export var emotion_portraits: Dictionary = {}


# -----------------------------------------------------------------------------
# Public API
# -----------------------------------------------------------------------------

## Get a portrait by emotion name. Returns the default portrait if the
## emotion doesn't exist in the dictionary, or if no portraits are set.
func get_portrait(emotion: String = "") -> Texture2D:
        # If no emotion requested, use the default.
        if emotion.is_empty():
                return portrait

        # Look up the emotion in the dictionary.
        # The .get() method returns the second argument (null here) if the
        # key doesn't exist, avoiding a crash.
        var override: Texture2D = emotion_portraits.get(emotion, null)
        if override != null:
                return override

        # Fallback: emotion requested but not found → use default.
        return portrait
