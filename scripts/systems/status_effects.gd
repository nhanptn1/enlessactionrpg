extends RefCounted
class_name StatusEffects

# Shared elemental status bookkeeping for EnemyBase and BossBase. Not a child
# Node (unlike a typical "StatusEffectManager" component) -- matches this
# project's own Strategy-pattern convention (MovementBehavior/AttackBehavior):
# static functions that read/write only through the passed-in `target`, no
# state of their own. `target` must expose `status: Dictionary` (element name
# -> seconds remaining), `sprite: AnimatedSprite2D`, `_base_modulate: Color`,
# and `take_damage(amount: float)`.
#
# Elemental skill-tree branch stats (fire_dps_mult, lightning_dps,
# *_spread_chance, frost_damage_amp, *_combo_bonus_mult, lightning_slow_bonus,
# fire_explode_on_death) live on Player, not here -- fetched on demand via
# _get_player(target) rather than threading extra params through every
# Projectile/TrapZone activate() call, since there's only ever one player.

const FIRE := "fire"
const LIGHTNING := "lightning"
const FROST := "frost"

const FIRE_DPS := 6.0
const FIRE_DURATION := 2.5
const FIRE_TICK_INTERVAL := 0.5  # FIRE_DURATION must be an exact multiple of this
const FIRE_COLOR := Color(1.6, 0.55, 0.4, 1.0)

const LIGHTNING_SLOW_MULT := 0.45
const LIGHTNING_DURATION := 1.8
const LIGHTNING_TICK_INTERVAL := 0.5  # only ticks damage if the player has lightning_dps > 0 (Static Charge)
const LIGHTNING_COLOR := Color(1.6, 1.6, 0.45, 1.0)

const FROST_DURATION := 1.6
const FROST_COLOR := Color(0.55, 0.85, 1.6, 1.0)

const FROSTFIRE_DAMAGE := 40.0
const FROSTFIRE_SHAKE_INTENSITY := 8.0
const FROSTFIRE_SHAKE_DURATION := 0.2

const SUPERCONDUCTOR_DAMAGE := 25.0
const SUPERCONDUCTOR_SPLASH_DAMAGE := 15.0
const SUPERCONDUCTOR_SPLASH_RADIUS := 80.0

const SPREAD_RADIUS := 90.0  # Ignite Trail / Ice Wall Nova / Chain Resonance
const EXPLODE_DAMAGE := 20.0
const EXPLODE_RADIUS := 90.0  # Explosive Volley

# (2026-07-17) Phase 3 pillar 2: tier-5 capstone passives (Inferno Heart/
# Absolute Zero/Overcharge, see resources/upgrades/*_t5_*.tres). Read directly
# off *_level >= 5 rather than a new bool flag -- fire_level/frost_level/
# lightning_level already track exactly this ("highest tier reached").
const CAPSTONE_TIER := 5
const FIRE_CAPSTONE_DPS_MULT := 1.5  # on top of fire_dps_mult, not replacing it
const FROST_CAPSTONE_COMBO_MULT := 2.0  # applies to both combos Frost participates in (Frostfire and Superconductor)
const LIGHTNING_CAPSTONE_COMBO_MULT := 2.0  # Superconductor only -- Lightning has no Fire combo

const TINT_PRIORITY := [FROST, LIGHTNING, FIRE]  # first active status in this order wins the tint


static func apply(target: Node, element: String, duration: float, allow_spread: bool = true) -> void:
	if not is_instance_valid(target):
		return
	target.status[element] = duration
	_refresh_tint(target)
	_evaluate_combos(target)
	if allow_spread:
		_try_spread(target, element, duration)


static func tick(target: Node, delta: float) -> void:
	if not is_instance_valid(target) or target.status.is_empty():
		return
	# Fire/Lightning DOT is throttled to a fixed tick interval rather than
	# applied every physics frame -- take_damage() also triggers the hit-flash
	# tween and hit sound, so calling it at 60Hz would spam both instead of
	# reading as a steady tick. Detect crossing a tick boundary via the
	# remaining-time countdown itself, no extra per-target field needed.
	var fire_old_remaining: float = target.status.get(FIRE, -1.0)
	var lightning_old_remaining: float = target.status.get(LIGHTNING, -1.0)
	var expired: Array = []
	for element in target.status:
		target.status[element] -= delta
		if target.status[element] <= 0.0:
			expired.append(element)
	var player := _get_player(target)
	if fire_old_remaining >= 0.0:
		var fire_new_remaining: float = maxf(target.status.get(FIRE, 0.0), 0.0)
		if int(fire_old_remaining / FIRE_TICK_INTERVAL) != int(fire_new_remaining / FIRE_TICK_INTERVAL):
			var dps_mult: float = player.fire_dps_mult if is_instance_valid(player) else 1.0
			if is_instance_valid(player) and player.fire_level >= CAPSTONE_TIER:
				dps_mult *= FIRE_CAPSTONE_DPS_MULT
			target.take_damage(FIRE_DPS * dps_mult * FIRE_TICK_INTERVAL, FIRE)
			if not is_instance_valid(target):
				return  # the burn tick itself killed it
	if lightning_old_remaining >= 0.0 and is_instance_valid(player) and player.lightning_dps > 0.0:
		var lightning_new_remaining: float = maxf(target.status.get(LIGHTNING, 0.0), 0.0)
		if int(lightning_old_remaining / LIGHTNING_TICK_INTERVAL) != int(lightning_new_remaining / LIGHTNING_TICK_INTERVAL):
			target.take_damage(player.lightning_dps * LIGHTNING_TICK_INTERVAL, LIGHTNING)
			if not is_instance_valid(target):
				return  # the shock tick itself killed it
	for element in expired:
		target.status.erase(element)
	_refresh_tint(target)


static func is_frozen(target: Node) -> bool:
	return target.status.has(FROST)


static func speed_multiplier(target: Node) -> float:
	if not target.status.has(LIGHTNING):
		return 1.0
	var player := _get_player(target)
	var bonus: float = player.lightning_slow_bonus if is_instance_valid(player) else 0.0
	return maxf(LIGHTNING_SLOW_MULT - bonus, 0.1)  # floored so Volt Arc never becomes a full stop -- that's Frost's identity


static func damage_amp(target: Node) -> float:
	# Brittle Frost: frozen enemies take extra damage from all sources.
	# Called from EnemyBase/BossBase.take_damage() before subtracting HP.
	if not target.status.has(FROST):
		return 1.0
	var player := _get_player(target)
	return 1.0 + (player.frost_damage_amp if is_instance_valid(player) else 0.0)


static func explode_on_death(target: Node) -> void:
	# Explosive Volley: called from EnemyBase/BossBase._die() when the dying
	# enemy was burning and the player has picked up this branch.
	if not is_instance_valid(target):
		return
	var player := _get_player(target)
	if not is_instance_valid(player) or player.fire_explode_on_death <= 0.0:
		return
	if not target.status.has(FIRE):
		return
	for enemy in target.get_tree().get_nodes_in_group("enemy"):
		if enemy == target or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_damage"):
			continue
		if target.global_position.distance_to(enemy.global_position) <= EXPLODE_RADIUS:
			enemy.take_damage(EXPLODE_DAMAGE, FIRE)


static func _try_spread(target: Node, element: String, duration: float) -> void:
	var player := _get_player(target)
	if not is_instance_valid(player):
		return
	var chance := 0.0
	match element:
		FIRE:
			chance = 1.0 if player.fire_level >= CAPSTONE_TIER else player.fire_spread_chance
		FROST:
			chance = 1.0 if player.frost_level >= CAPSTONE_TIER else player.frost_spread_chance
		LIGHTNING:
			chance = 1.0 if player.lightning_level >= CAPSTONE_TIER else player.lightning_spread_chance
	if chance <= 0.0 or randf() >= chance:
		return
	var nearby := _find_nearby_enemy(target)
	if is_instance_valid(nearby):
		apply(nearby, element, duration, false)  # false: don't chain-spread from the spread target


static func _find_nearby_enemy(target: Node) -> Node:
	if not is_instance_valid(target):
		return null
	var candidates: Array = []
	for enemy in target.get_tree().get_nodes_in_group("enemy"):
		if enemy == target or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("apply_status"):
			continue
		if target.global_position.distance_to(enemy.global_position) <= SPREAD_RADIUS:
			candidates.append(enemy)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


static func _evaluate_combos(target: Node) -> void:
	var player := _get_player(target)
	if target.status.has(FIRE) and target.status.has(FROST):
		var frost_mult: float = 1.0 + (player.frost_combo_bonus_mult if is_instance_valid(player) else 0.0)
		if is_instance_valid(player) and player.frost_level >= CAPSTONE_TIER:
			frost_mult *= FROST_CAPSTONE_COMBO_MULT
		target.take_damage(FROSTFIRE_DAMAGE * frost_mult)
		var cam := target.get_viewport().get_camera_2d()
		if is_instance_valid(cam) and cam.has_method("shake"):
			cam.shake(FROSTFIRE_SHAKE_INTENSITY, FROSTFIRE_SHAKE_DURATION)
		_clear_all(target)
	elif target.status.has(FROST) and target.status.has(LIGHTNING):
		var combo_mult: float = 1.0
		if is_instance_valid(player):
			combo_mult += player.frost_combo_bonus_mult + player.lightning_combo_bonus_mult
			if player.frost_level >= CAPSTONE_TIER:
				combo_mult *= FROST_CAPSTONE_COMBO_MULT
			if player.lightning_level >= CAPSTONE_TIER:
				combo_mult *= LIGHTNING_CAPSTONE_COMBO_MULT
		target.take_damage(SUPERCONDUCTOR_DAMAGE * combo_mult)
		_splash_nearby(target)
		_clear_all(target)


static func _splash_nearby(target: Node) -> void:
	if not is_instance_valid(target):
		return
	for enemy in target.get_tree().get_nodes_in_group("enemy"):
		if enemy == target or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_damage"):
			continue
		if target.global_position.distance_to(enemy.global_position) <= SUPERCONDUCTOR_SPLASH_RADIUS:
			enemy.take_damage(SUPERCONDUCTOR_SPLASH_DAMAGE)


static func _clear_all(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.status.clear()
	_refresh_tint(target)


static func _refresh_tint(target: Node) -> void:
	if not is_instance_valid(target) or not is_instance_valid(target.sprite):
		return
	for element in TINT_PRIORITY:
		if target.status.has(element):
			target.sprite.modulate = _color_for(element)
			return
	target.sprite.modulate = target._base_modulate


static func _color_for(element: String) -> Color:
	match element:
		FIRE:
			return FIRE_COLOR
		LIGHTNING:
			return LIGHTNING_COLOR
		FROST:
			return FROST_COLOR
	return Color.WHITE


static func _get_player(target: Node) -> Node:
	if not is_instance_valid(target):
		return null
	return target.get_tree().get_first_node_in_group("player")
