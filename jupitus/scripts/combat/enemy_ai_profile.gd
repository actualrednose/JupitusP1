extends Resource
class_name EnemyAIProfile

## Used when no conditional table matches. Enter each action and its percentage
## chance here. A conventional table should total 100%, but non-100 totals are
## normalized so the profile remains usable while it is being edited.
@export var base_actions: Array[EnemyAIActionChance] = []

## Conditional replacement tables, evaluated from top to bottom. The first
## matching table is used and later matching tables are ignored, so put the
## most specific or most important situations first.
@export var conditional_tables: Array[EnemyAIConditionalTable] = []


func get_action_table(
	actor: CombatantState,
	session: BattleSession
) -> Array[EnemyAIActionChance]:
	for table in conditional_tables:
		if table != null and table.matches(actor, session):
			return table.actions

	return base_actions


func get_matching_table_name(
	actor: CombatantState,
	session: BattleSession
) -> String:
	for table in conditional_tables:
		if table != null and table.matches(actor, session):
			return table.table_name

	return "Base actions"
