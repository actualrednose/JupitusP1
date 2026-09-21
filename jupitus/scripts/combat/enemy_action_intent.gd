extends RefCounted
class_name EnemyActionIntent

var actor: CombatantState
var ability: AbilityDefinition
var target: CombatantState
var intent_type: EnemyAIActionChance.IntentType
var display_text: String
var source_table_name: String


func _init(
	source_actor: CombatantState,
	source_entry: EnemyAIActionChance,
	source_target: CombatantState,
	table_name: String
) -> void:
	actor = source_actor
	ability = source_entry.ability
	target = source_target
	intent_type = _resolve_intent_type(source_entry)
	source_table_name = table_name

	if not source_entry.intent_text_override.is_empty():
		display_text = source_entry.intent_text_override
	elif intent_type == EnemyAIActionChance.IntentType.UNKNOWN:
		display_text = "???"
	else:
		display_text = ability.display_name


func get_category_name() -> String:
	match intent_type:
		EnemyAIActionChance.IntentType.ATTACK:
			return "Attack"
		EnemyAIActionChance.IntentType.DEFEND:
			return "Defend"
		EnemyAIActionChance.IntentType.SUPPORT:
			return "Support"
		EnemyAIActionChance.IntentType.POWER_ATTACK:
			return "Power Attack"
		EnemyAIActionChance.IntentType.UNKNOWN:
			return "Unknown"

	return "Unknown"


func _resolve_intent_type(
	entry: EnemyAIActionChance
) -> EnemyAIActionChance.IntentType:
	if entry.intent_type != EnemyAIActionChance.IntentType.AUTOMATIC:
		return entry.intent_type

	if ability.is_power_attack:
		return EnemyAIActionChance.IntentType.POWER_ATTACK

	if (
		ability.kind == AbilityDefinition.Kind.GUARD
		or ability.has_effect_type(
			AbilityEffectDefinition.EffectType.GUARD
		)
	):
		return EnemyAIActionChance.IntentType.DEFEND

	if (
		ability.has_effect_type(
			AbilityEffectDefinition.EffectType.HEAL
		)
		or ability.has_effect_type(
			AbilityEffectDefinition.EffectType.CLEANSE
		)
		or ability.has_effect_type(
			AbilityEffectDefinition.EffectType.REVIVE
		)
	):
		return EnemyAIActionChance.IntentType.SUPPORT

	if (
		ability.has_effect_type(
			AbilityEffectDefinition.EffectType.DAMAGE
		)
		or ability.has_effect_type(
			AbilityEffectDefinition.EffectType.STAGGER
		)
	):
		return EnemyAIActionChance.IntentType.ATTACK

	return EnemyAIActionChance.IntentType.UNKNOWN
