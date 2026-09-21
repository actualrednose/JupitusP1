extends Resource
class_name EnemyAIActionChance

enum IntentType {
	AUTOMATIC,
	ATTACK,
	DEFEND,
	SUPPORT,
	POWER_ATTACK,
	UNKNOWN,
}

## The ability this entry may choose.
@export var ability: AbilityDefinition = null

## This ability's percentage chance relative to the other usable entries in
## the same table. A table totaling 100 behaves as literal percentages, such
## as 40/30/30. Other totals are normalized, so 2/1 behaves as 66.7%/33.3%.
## Set this to zero to temporarily disable the action without deleting it.
@export_range(0.0, 100.0, 0.1, "suffix:%") var chance_percent: float = 0.0

## Controls the category shown to the player:
## - Automatic: infer Attack, Defend, Support, or Power Attack from the ability.
## - Attack: an ordinary offensive action.
## - Defend: guarding or another defensive action.
## - Support: healing, cleansing, revival, or another helpful action.
## - Power Attack: a dangerous attack that should receive extra emphasis.
## - Unknown: deliberately hide what kind of action is coming.
@export var intent_type: IntentType = IntentType.AUTOMATIC

## Optional text shown above the enemy instead of the ability's display name.
## Leave this empty to display the ability name.
@export var intent_text_override: String = ""
