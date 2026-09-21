extends Resource
class_name AbilityEffectDefinition

enum EffectType {
	DAMAGE,
	HEAL,
	TEMPO,
	GUARD,
	APPLY_STATUS,
	CLEANSE,
	REVIVE,
	STAGGER,
}

enum TargetType {
	SELECTED_ENEMY,
	SELECTED_ALLY,
	SELF,
	ALL_ALLIES,
	ALL_ENEMIES,
}

enum TimingRequirement {
	ANY,
	HIT,
	GOOD_OR_BETTER,
	PERFECT,
}

@export_group("Effect")
@export var effect_type: EffectType = EffectType.DAMAGE
@export var target_type: TargetType = TargetType.SELECTED_ENEMY
@export_range(-999, 999) var value_min: int = 0
@export_range(-999, 999) var value_max: int = 0
@export_range(0.0, 1.0, 0.01) var application_chance: float = 1.0

@export_group("Timing")
@export var timing_requirement: TimingRequirement = TimingRequirement.ANY
@export var scales_with_timing: bool = false
## Resolves this effect once for every successful timing-minigame input.
@export var repeat_for_each_timing_success: bool = false

@export_group("Damage")
@export_range(0, 100) var target_tempo_gain_min: int = 0
@export_range(0, 100) var target_tempo_gain_max: int = 0

@export_group("Status")
@export var status: StatusEffectDefinition = null
## Zero uses the status definition's default duration.
@export_range(0, 99) var status_duration_override: int = 0


func roll_value(rng: RandomNumberGenerator) -> int:
	var minimum := mini(value_min, value_max)
	var maximum := maxi(value_min, value_max)
	return rng.randi_range(minimum, maximum)


func roll_target_tempo_gain(rng: RandomNumberGenerator) -> int:
	var minimum := mini(
		target_tempo_gain_min,
		target_tempo_gain_max
	)
	var maximum := maxi(
		target_tempo_gain_min,
		target_tempo_gain_max
	)
	return rng.randi_range(minimum, maximum)


func meets_timing_requirement(timing_result: int) -> bool:
	match timing_requirement:
		TimingRequirement.ANY:
			return true
		TimingRequirement.HIT:
			return timing_result != BattleAction.TimingResult.MISS
		TimingRequirement.GOOD_OR_BETTER:
			return (
				timing_result == BattleAction.TimingResult.GOOD
				or timing_result == BattleAction.TimingResult.PERFECT
			)
		TimingRequirement.PERFECT:
			return timing_result == BattleAction.TimingResult.PERFECT

	return false
