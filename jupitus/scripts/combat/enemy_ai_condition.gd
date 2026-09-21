extends Resource
class_name EnemyAICondition

enum ConditionType {
	SELF_HP_BELOW_PERCENT,
	SELF_HP_AT_OR_ABOVE_PERCENT,
	SELF_TEMPO_AT_LEAST,
	SELF_TEMPO_BELOW,
	ANY_ALLY_DEFEATED,
	ALL_ALLIES_DEFEATED,
	LIVING_ALLY_COUNT_AT_MOST,
	TURN_NUMBER_AT_LEAST,
	HAS_STATUS,
	DOES_NOT_HAVE_STATUS,
}

## Selects what this condition checks:
## - Self HP Below Percent: true when HP is strictly below Threshold Percent.
## - Self HP At Or Above Percent: true at or above Threshold Percent.
## - Self Tempo At Least: true at or above Threshold Value.
## - Self Tempo Below: true strictly below Threshold Value.
## - Any Ally Defeated: true when at least one other enemy has been defeated.
## - All Allies Defeated: true when every other enemy has been defeated. This
##   is false for an enemy that started without allies.
## - Living Ally Count At Most: compares other living enemies to Threshold Value.
## - Turn Number At Least: true on or after Threshold Value (first turn is 1).
## - Has Status / Does Not Have Status: checks Status ID on this enemy.
@export var condition_type: ConditionType = (
	ConditionType.SELF_HP_BELOW_PERCENT
)

## Used by the two HP percentage conditions. For example, 50 means half HP.
@export_range(0.0, 100.0, 0.1, "suffix:%") var threshold_percent: float = 50.0

## Used by Tempo, living ally count, and turn number conditions.
@export_range(0, 999) var threshold_value: int = 0

## Used only by Has Status and Does Not Have Status.
@export var status_id: StringName = &"status"


func matches(
	actor: CombatantState,
	session: BattleSession
) -> bool:
	if actor == null or session == null:
		return false

	match condition_type:
		ConditionType.SELF_HP_BELOW_PERCENT:
			return _get_hp_percent(actor) < threshold_percent

		ConditionType.SELF_HP_AT_OR_ABOVE_PERCENT:
			return _get_hp_percent(actor) >= threshold_percent

		ConditionType.SELF_TEMPO_AT_LEAST:
			return actor.current_tempo >= threshold_value

		ConditionType.SELF_TEMPO_BELOW:
			return actor.current_tempo < threshold_value

		ConditionType.ANY_ALLY_DEFEATED:
			for ally in _get_other_allies(actor, session):
				if ally.is_defeated():
					return true

			return false

		ConditionType.ALL_ALLIES_DEFEATED:
			var allies := _get_other_allies(actor, session)

			if allies.is_empty():
				return false

			for ally in allies:
				if not ally.is_defeated():
					return false

			return true

		ConditionType.LIVING_ALLY_COUNT_AT_MOST:
			var living_count := 0

			for ally in _get_other_allies(actor, session):
				if not ally.is_defeated():
					living_count += 1

			return living_count <= threshold_value

		ConditionType.TURN_NUMBER_AT_LEAST:
			return session.turn_number >= threshold_value

		ConditionType.HAS_STATUS:
			return actor.has_status(status_id)

		ConditionType.DOES_NOT_HAVE_STATUS:
			return not actor.has_status(status_id)

	return false


func _get_hp_percent(actor: CombatantState) -> float:
	if actor.definition == null or actor.definition.max_hp <= 0:
		return 0.0

	return (
		float(actor.current_hp)
		/ float(actor.definition.max_hp)
		* 100.0
	)


func _get_other_allies(
	actor: CombatantState,
	session: BattleSession
) -> Array[CombatantState]:
	var allies: Array[CombatantState] = []
	var team_members := session.enemies

	if actor.team == CombatantState.Team.PLAYER:
		team_members = session.player_party

	for ally in team_members:
		if ally != actor:
			allies.append(ally)

	return allies
