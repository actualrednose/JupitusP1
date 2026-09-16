# player_state.gd
# -----------------------------------------------------------------------------
# Autoload singleton that holds persistent player state across scene changes.
#
# Why a singleton instead of persisting the player node itself?
#   - The player node is destroyed and recreated on each scene change (it's
#     a child of the scene, not the root). So any state on the player node
#     (HP, inventory, etc.) would be lost.
#   - This singleton lives at the root of the scene tree and is never
#     destroyed (except on game exit). It's the canonical place to store
#     things that need to survive scene transitions.
#
# What goes here:
#   - Currency (money)
#   - Inventory (will add when we build the inventory system)
#   - Party roster (will add when we build the party system)
#   - Quest / progression flags (separate from DialogueManager.flags,
#     which are for dialogue branching)
#   - HP / status (will add when we build combat)
#
# What does NOT go here:
#   - Player position (use spawn points in each scene instead)
#   - Player velocity (resets to zero on each scene change anyway)
#   - Dialogue branching flags (those live in DialogueManager.flags)
#
# To set up:
#   1. Project Settings → Globals → Add
#   2. Path: res://scripts/systems/player_state.gd
#   3. Name: PlayerState
#   4. Make sure "Enabled" is checked
# -----------------------------------------------------------------------------

extends Node

# --- Signals ---

# Emitted when currency changes. UI elements (like a money counter) can
# connect to this to update their display.
signal currency_changed(new_amount: int)

# Emitted when any flag changes. Useful for quest UI, achievement checks, etc.
signal flag_set(flag_name: String, value: Variant)

# --- Public state ---

# Player's current money. Use add_currency / spend_currency instead of
# modifying this directly, so signals fire correctly.
var currency: int = 0

# Generic key/value store for game progression state.
# Examples: "met_robber" = true, "milk_bought" = true, "doors_opened" = 3
#
# This is separate from DialogueManager.flags:
#   - DialogueManager.flags: set by dialogue choices, used for dialogue branching
#   - PlayerState.flags: set by game logic, used for quest/progression checks
#
# In practice, you might want to set BOTH when a choice has story implications.
# For now, this separation keeps the systems decoupled.
var flags: Dictionary = {}


# -----------------------------------------------------------------------------
# Currency API
# -----------------------------------------------------------------------------

## Add currency. Pass a positive int. Triggers currency_changed signal.
func add_currency(amount: int) -> void:
	if amount == 0:
		return
	currency += amount
	currency_changed.emit(currency)


## Try to spend currency. Returns true if the player had enough (and it was
## deducted), false if they didn't (no deduction happens).
##
## Example:
##   if PlayerState.spend_currency(50):
##       give_item_to_player(...)
##   else:
##       show_message("Not enough money!")
func spend_currency(amount: int) -> bool:
	if currency < amount:
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true


# -----------------------------------------------------------------------------
# Flag API
# -----------------------------------------------------------------------------

## Set a flag. Default value is true, but you can pass any Variant
## (int, string, etc.) if you need more than just on/off state.
func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value
	flag_set.emit(flag_name, value)


## Get a flag's value. Returns `default` if the flag isn't set.
## For boolean flags, use get_flag("name", false).
func get_flag(flag_name: String, default: Variant = null) -> Variant:
	return flags.get(flag_name, default)


## Returns true if the flag exists and is "truthy" (not false, not null, not 0).
## Convenient for `if PlayerState.has_flag("met_robber"):` checks.
func has_flag(flag_name: String) -> bool:
	if not flags.has(flag_name):
		return false

	var value: Variant = flags.get(flag_name, null)

	match typeof(value):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return bool(value)
		TYPE_INT:
			return int(value) != 0
		TYPE_FLOAT:
			return not is_zero_approx(float(value))
		TYPE_STRING, TYPE_STRING_NAME:
			return not str(value).is_empty()
		_:
			return true


## Remove a flag entirely (as if it was never set).
## Useful for "undo" scenarios or debug resets.
func clear_flag(flag_name: String) -> void:
	flags.erase(flag_name)


# -----------------------------------------------------------------------------
# Reset API
# -----------------------------------------------------------------------------

## Clear ALL state. Call this when starting a new game, or before loading
## a save (so the save's values can be applied cleanly).
##
## WARNING: This wipes everything. Don't call mid-game unless you mean it.
func reset() -> void:
	currency = 0
	flags.clear()
	currency_changed.emit(currency)


# -----------------------------------------------------------------------------
# Save / Load hooks (stubs for future save system)
# -----------------------------------------------------------------------------
#
# When we build the save system, these methods will serialize PlayerState
# to a dictionary (which can then be saved as JSON or a ConfigFile).
# For now, they're stubs.

func to_dict() -> Dictionary:
	return {
		"currency": currency,
		"flags": flags.duplicate(),
	}


func from_dict(data: Dictionary) -> void:
	currency = data.get("currency", 0)
	flags = data.get("flags", {}).duplicate()
	currency_changed.emit(currency)
