extends Resource
class_name CombatantDefinition

@export_group("Identity")
@export var combatant_id: StringName = &"combatant"
@export var display_name: String = "Combatant"
@export var icon: Texture2D = null
@export var is_player_character: bool = true

@export_group("Base Stats")
@export_range(1, 9999) var max_hp: int = 100
@export_range(0, 100) var max_tempo: int = 100
@export_range(0, 999) var speed: int = 10

@export_group("Abilities")
@export var main_attack: AbilityDefinition = null
@export var skills: Array[AbilityDefinition] = []
@export var guard_ability: AbilityDefinition = null

@export_group("Enemy Behavior")
## Optional power attack the enemy AI can prepare.
@export var power_attack: AbilityDefinition = null

## Percentage-based decision profile used when this combatant is an enemy.
## Leave this empty only for player characters or unfinished test enemies.
@export var ai_profile: EnemyAIProfile = null
