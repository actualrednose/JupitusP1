extends RefCounted
class_name BattleAI


static func choose_intent(
	actor: CombatantState,
	profile: EnemyAIProfile,
	session: BattleSession
) -> EnemyActionIntent:
	if (
		actor == null
		or profile == null
		or session == null
		or actor.is_defeated()
	):
		return null

	var source_table := profile.get_action_table(actor, session)
	var usable_entries: Array[EnemyAIActionChance] = []
	var targets: Dictionary = {}
	var total_chance := 0.0

	for entry in source_table:
		if (
			entry == null
			or entry.ability == null
			or entry.chance_percent <= 0.0
		):
			continue

		if (
			entry.ability.kind != AbilityDefinition.Kind.GUARD
			and not actor.can_use_ability(entry.ability)
		):
			continue

		var target_result := _find_target(
			actor,
			entry.ability,
			session
		)

		if not bool(target_result["valid"]):
			continue

		usable_entries.append(entry)
		targets[entry] = target_result["target"]
		total_chance += entry.chance_percent

	if usable_entries.is_empty() or total_chance <= 0.0:
		return null

	var roll := session.rng.randf_range(0.0, total_chance)
	var cumulative := 0.0
	var selected_entry: EnemyAIActionChance = usable_entries.back()

	for entry in usable_entries:
		cumulative += entry.chance_percent

		if roll < cumulative:
			selected_entry = entry
			break

	return EnemyActionIntent.new(
		actor,
		selected_entry,
		targets[selected_entry],
		profile.get_matching_table_name(actor, session)
	)


static func _find_target(
	actor: CombatantState,
	ability: AbilityDefinition,
	session: BattleSession
) -> Dictionary:
	var needs_enemy := false
	var needs_ally := false
	var needs_defeated_ally := false

	for effect in ability.effects:
		if effect == null:
			continue

		match effect.target_type:
			AbilityEffectDefinition.TargetType.SELECTED_ENEMY:
				needs_enemy = true

			AbilityEffectDefinition.TargetType.SELECTED_ALLY:
				needs_ally = true

				if (
					effect.effect_type
					== AbilityEffectDefinition.EffectType.REVIVE
				):
					needs_defeated_ally = true

	if needs_enemy and needs_ally:
		push_warning(
			"BattleAI: '%s' mixes selected enemy and selected ally effects"
			% ability.display_name
		)
		return {"valid": false, "target": null}

	if needs_enemy:
		for opponent in _get_opponents(actor, session):
			if not opponent.is_defeated():
				return {"valid": true, "target": opponent}

		return {"valid": false, "target": null}

	if needs_ally:
		var allies := _get_allies(actor, session)

		if needs_defeated_ally:
			for ally in allies:
				if ally.is_defeated():
					return {"valid": true, "target": ally}

			return {"valid": false, "target": null}

		for ally in allies:
			if ally != actor and not ally.is_defeated():
				return {"valid": true, "target": ally}

		if not actor.is_defeated():
			return {"valid": true, "target": actor}

		return {"valid": false, "target": null}

	return {"valid": true, "target": null}


static func _get_allies(
	actor: CombatantState,
	session: BattleSession
) -> Array[CombatantState]:
	if actor.team == CombatantState.Team.PLAYER:
		return session.player_party

	return session.enemies


static func _get_opponents(
	actor: CombatantState,
	session: BattleSession
) -> Array[CombatantState]:
	if actor.team == CombatantState.Team.PLAYER:
		return session.enemies

	return session.player_party
