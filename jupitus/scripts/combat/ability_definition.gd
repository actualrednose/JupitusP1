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
@export var kind: Kind = Kind.SKILL

@export_group("Cost and Power")
## Tempo required to use this ability.
@export_range(0, 100) var tempo_cost: int = 0

## Base damage or effect strength.
@export_range(0, 999) var power: int = 10

@export_group("Tempo")
## Tempo gained by the user when this ability is successfully used.
@export_range(0, 10) var tempo_gain_on_use_min: int = 0
@export_range(0, 10) var tempo_gain_on_use_max: int = 0

## Tempo gained by the target when this ability deals damage.
@export_range(0, 10) var tempo_gain_on_damage_min: int = 5
@export_range(0, 10) var tempo_gain_on_damage_max: int = 10

@export_group("Turn Order")
## Higher-priority actions resolve first.
@export var action_priority: int = 0

@export_group("Timing")
@export var timing_type: TimingType = TimingType.NONE

## A PERFECT result can disrupt a target's prepared power attack.
@export var disrupts_power_attack_on_perfect: bool = false

@export_group("Special Behavior")
## Used by enemy abilities that visibly prepare a dangerous attack.
@export var is_power_attack: bool = false


func get_tempo_gain_on_use() -> int:
	var minimum: int = mini(
		tempo_gain_on_use_min,
		tempo_gain_on_use_max
	)
	var maximum: int = maxi(
		tempo_gain_on_use_min,
		tempo_gain_on_use_max
	)

	return randi_range(minimum, maximum)


func get_tempo_gain_on_damage() -> int:
	var minimum: int = mini(
		tempo_gain_on_damage_min,
		tempo_gain_on_damage_max
	)
	var maximum: int = maxi(
		tempo_gain_on_damage_min,
		tempo_gain_on_damage_max
	)

	return randi_range(minimum, maximum)
