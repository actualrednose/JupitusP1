extends Resource
class_name EnemyAIConditionalTable

enum MatchMode {
	ALL,
	ANY,
}

## A descriptive editor-only name, such as "Below 50% HP" or "Ally Downed".
@export var table_name: String = "Conditional actions"

## Controls how this table's Conditions are evaluated:
## - All: every condition must be true.
## - Any: at least one condition must be true.
## An empty condition list never matches.
@export var match_mode: MatchMode = MatchMode.ALL

## Conditions that activate this replacement action table.
@export var conditions: Array[EnemyAICondition] = []

## The complete replacement percentage distribution used while this table
## matches. These do not modify individual base chances; they replace the
## entire base action table for this decision.
@export var actions: Array[EnemyAIActionChance] = []


func matches(
	actor: CombatantState,
	session: BattleSession
) -> bool:
	if conditions.is_empty():
		return false

	if match_mode == MatchMode.ALL:
		for condition in conditions:
			if (
				condition == null
				or not condition.matches(actor, session)
			):
				return false

		return true

	for condition in conditions:
		if (
			condition != null
			and condition.matches(actor, session)
		):
			return true

	return false
