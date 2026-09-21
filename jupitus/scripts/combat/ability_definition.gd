extends Resource
class_name AbilityDefinition

enum Kind {
	REGULAR_ATTACK,
	SKILL,
	GUARD,
	ITEM,
}

enum TimingType {
	NONE,
	CROSSHAIR_HEAD,
}

@export_group("Identity")
@export var display_name: String = "Ability"
@export var action_verb: String = "attacked"
@export var kind: Kind = Kind.SKILL

@export_group("Cost")
## Tempo required to use this ability.
@export_range(0, 100) var tempo_cost: int = 0

@export_group("Effects")
@export var effects: Array[AbilityEffectDefinition] = []

@export_group("Turn Order")
## Higher-priority actions resolve first.
@export var action_priority: int = 0

@export_group("Timing")
## NONE resolves immediately. CROSSHAIR_HEAD pauses before the action and
## asks the player to stop a horizontal crosshair over the target's head.
@export var timing_type: TimingType = TimingType.NONE

@export_group("Special Behavior")
## Used by enemy abilities that visibly prepare a dangerous attack.
@export var is_power_attack: bool = false


func has_effect_type(
	effect_type: AbilityEffectDefinition.EffectType
) -> bool:
	for effect in effects:
		if (
			effect != null
			and effect.effect_type == effect_type
		):
			return true

	return false
