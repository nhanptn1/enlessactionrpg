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
const LIGHTNING_TICK_INTERVAL := 0.5
# (2026-07-24) Shock now does baseline damage from tier 1, like burn does.
# User report: "the lightning skill path seem slower and worse to play than
# another skill path". Two measured asymmetries caused it, both here:
#   1. Shock's damage tick was gated on `player.lightning_dps > 0`, and the ONLY
#      thing granting that stat is the tier-4 card -- so Lightning had literally
#      no damage-over-time for its first three tiers, while Fire burns from
#      tier 1 and Frost freezes from tier 1.
#   2. Even after tier 4 the tick was FLAT, while burn is multiplied by the
#      enemy's own wave HP scaling (entry 80's fix, applied to Fire and never
#      to Lightning). At wave 50 that left burn at ~54 per tick against shock's
#      0.5 -- a ~100x gap on the same axis.
# Set below Fire's 6.0 on purpose: Fire is the pure-damage element, while
# Lightning also stuns, slows and chains. Tier 4's `lightning_dps` still stacks
# on top of this as a flat bonus.
const LIGHTNING_DPS := 5.0
const LIGHTNING_COLOR := Color(1.6, 1.6, 0.45, 1.0)
# (2026-07-22) Shock now opens with a brief hard stun before settling into the
# slow above -- user report: at wave 30+ shocked enemies "don't stop". The slow
# is a *multiplier*, so as wave speed scaling climbed it stopped reading as a
# slow at all; a short guaranteed full stop makes a shock land visibly at any
# wave, while the slow keeps Frost's full-freeze identity intact.
const LIGHTNING_STUN_DURATION := 0.35
# Stored in the same `status` dictionary as the elements, but it is NOT an
# element: it never tints, never combos, and never spreads. Tracking it there
# means tick() expires it for free with the same countdown as everything else.
const STUN := "stun"

# (2026-07-22) Bosses deliberately take no full movement lock (a stun-locked
# boss would trivialize the fight), but total immunity made Frost/Lightning feel
# useless in boss fights -- and every 10th wave is a boss. A single modest walk
# slow while afflicted by either control element is the middle ground. Applies
# to the walk only; attack moves (charge/leap) keep their telegraphed timing.
const BOSS_STATUS_SLOW_MULT := 0.7

const FROST_DURATION := 1.6
const FROST_COLOR := Color(0.55, 0.85, 1.6, 1.0)

const FROSTFIRE_DAMAGE := 40.0

const SUPERCONDUCTOR_DAMAGE := 25.0
const SUPERCONDUCTOR_SPLASH_DAMAGE := 15.0
const SUPERCONDUCTOR_SPLASH_RADIUS := 80.0

# (2026-07-22) Overload: the Fire+Lightning combo, the third pair, only made
# reachable by the late-game fusion that applies both statuses (before fusions
# existed there was no way to reliably stack fire+lightning, so this pair had
# no combo at all). A burning + shocked enemy discharges -- a burst plus a wider
# splash than Superconductor, fitting a fire/lightning "explosion" read.
const OVERLOAD_DAMAGE := 30.0
const OVERLOAD_SPLASH_DAMAGE := 18.0
const OVERLOAD_SPLASH_RADIUS := 110.0

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


static func apply(target: Node, element: String, duration: float, allow_spread: bool = true, from_fusion: bool = false) -> void:
	if not is_instance_valid(target):
		return
	target.status[element] = duration
	if element == LIGHTNING:
		# Set directly rather than through apply() -- STUN is not an element, so
		# it must not spread, tint, or take part in combo evaluation.
		target.status[STUN] = LIGHTNING_STUN_DURATION
	_refresh_tint(target)
	_evaluate_combos(target)  # may deal combo damage + _clear_all, possibly freeing target
	if not is_instance_valid(target):
		return
	if allow_spread:
		_try_spread(target, element, duration)
		if not is_instance_valid(target):
			return
	# (2026-07-22) Elemental fusion: if the player has maxed the two lines of a
	# fusion involving `element`, their attacks also carry the partner status --
	# so applying `element` here also applies the partner, which makes the pair's
	# combo (evaluated in the recursive apply below) fire reliably. `from_fusion`
	# guards against infinite ping-pong (partner re-triggering the original).
	if from_fusion:
		return
	var player := _get_player(target)
	if not is_instance_valid(player):
		return
	for partner_el in player.get_fusion_partners(element):
		if not is_instance_valid(target):
			return
		if target.status.has(partner_el):
			continue
		apply(target, partner_el, duration, false, true)


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
			target.take_damage(FIRE_DPS * dps_mult * FIRE_TICK_INTERVAL * _wave_hp_scale(target), FIRE)
			if not is_instance_valid(target):
				return  # the burn tick itself killed it
	if lightning_old_remaining >= 0.0:
		var lightning_new_remaining: float = maxf(target.status.get(LIGHTNING, 0.0), 0.0)
		if int(lightning_old_remaining / LIGHTNING_TICK_INTERVAL) != int(lightning_new_remaining / LIGHTNING_TICK_INTERVAL):
			# No longer gated on the tier-4 stat -- LIGHTNING_DPS is the baseline
			# and `lightning_dps` stacks on top, mirroring how FIRE_DPS and
			# fire_dps_mult relate. Scaled by the same wave multiplier burn uses,
			# so a shock stays as relevant at wave 60 as at wave 1.
			var bonus_dps: float = player.lightning_dps if is_instance_valid(player) else 0.0
			target.take_damage((LIGHTNING_DPS + bonus_dps) * LIGHTNING_TICK_INTERVAL * _wave_hp_scale(target), LIGHTNING)
			if not is_instance_valid(target):
				return  # the shock tick itself killed it
	for element in expired:
		target.status.erase(element)
	_refresh_tint(target)


static func is_frozen(target: Node) -> bool:
	return target.status.has(FROST)


static func is_stunned(target: Node) -> bool:
	# Shock's opening hard stop (see LIGHTNING_STUN_DURATION). Regular enemies
	# only -- BossBase never checks this, bosses just get the walk slow below.
	return target.status.has(STUN)


static func boss_speed_multiplier(target: Node) -> float:
	# Bosses are never fully stopped; worst case they creep at BOSS_STATUS_SLOW_MULT
	# while chilled or shocked. Callers must recompute velocity from its base each
	# frame rather than multiplying in place, or this would compound to zero.
	if target.status.has(FROST) or target.status.has(LIGHTNING):
		return BOSS_STATUS_SLOW_MULT
	return 1.0


static func _wave_hp_scale(target: Node) -> float:
	# (2026-07-22) Burn was a flat FIRE_DPS while enemy HP scales up to
	# WaveManager.HP_MULT_CEILING (12x), so a late-wave burn was proportionally
	# negligible. Scaling the tick by the same multiplier the wave applied to
	# that enemy's HP keeps burn exactly as effective at wave 60 as at wave 1
	# (same number of ticks to kill) rather than making it stronger.
	var m = target.get("_hp_mult")
	if typeof(m) != TYPE_FLOAT and typeof(m) != TYPE_INT:
		return 1.0
	return maxf(float(m), 1.0)


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
		_combo_feedback(target, FROSTFIRE_DAMAGE * frost_mult, FROSTFIRE_COLOR, "frostfire")
		target.take_damage(FROSTFIRE_DAMAGE * frost_mult)
		_clear_all(target)
	elif target.status.has(FROST) and target.status.has(LIGHTNING):
		var combo_mult: float = 1.0
		if is_instance_valid(player):
			combo_mult += player.frost_combo_bonus_mult + player.lightning_combo_bonus_mult
			if player.frost_level >= CAPSTONE_TIER:
				combo_mult *= FROST_CAPSTONE_COMBO_MULT
			if player.lightning_level >= CAPSTONE_TIER:
				combo_mult *= LIGHTNING_CAPSTONE_COMBO_MULT
		_combo_feedback(target, SUPERCONDUCTOR_DAMAGE * combo_mult, SUPERCONDUCTOR_COLOR, "superconductor")
		target.take_damage(SUPERCONDUCTOR_DAMAGE * combo_mult)
		_splash_nearby(target, SUPERCONDUCTOR_SPLASH_DAMAGE, SUPERCONDUCTOR_SPLASH_RADIUS)
		_clear_all(target)
	elif target.status.has(FIRE) and target.status.has(LIGHTNING):
		# Overload -- the Fire+Lightning combo (fusion-only, see the consts above).
		var overload_mult: float = 1.0
		if is_instance_valid(player):
			overload_mult += player.lightning_combo_bonus_mult
			if player.fire_level >= CAPSTONE_TIER:
				overload_mult *= FIRE_CAPSTONE_DPS_MULT
			if player.lightning_level >= CAPSTONE_TIER:
				overload_mult *= LIGHTNING_CAPSTONE_COMBO_MULT
		_combo_feedback(target, OVERLOAD_DAMAGE * overload_mult, OVERLOAD_COLOR, "overload")
		target.take_damage(OVERLOAD_DAMAGE * overload_mult)
		_splash_nearby(target, OVERLOAD_SPLASH_DAMAGE, OVERLOAD_SPLASH_RADIUS)
		_clear_all(target)


# (2026-07-23) Combat juice pass. The three fusion combos used to resolve with
# nothing but a damage number change and (for two of them) a camera shake --
# the game's headline late-game mechanic looked like ordinary chip damage.
# Each now gets a signature burst in its own colour, a floating readout, and a
# beat of hitstop, so a combo proc is unmistakable.
const FROSTFIRE_COLOR := Color(0.75, 0.9, 1.0, 1.0)
const SUPERCONDUCTOR_COLOR := Color(0.7, 0.85, 1.0, 1.0)
const OVERLOAD_COLOR := Color(1.0, 0.65, 0.25, 1.0)
# (2026-07-23) 78 -> 200. A fusion is the reward for maxing TWO lines, but its
# detonation was drawn SMALLER than an ordinary elemental burst (skill
# burst_radius runs 50-170, so Ice Wall Nova alone out-sized every fusion).
# 200 puts a fusion clearly above the largest normal effect in the game, which
# is what the user asked for -- fusions should out-highlight element skills,
# not blend in with them.
const COMBO_FLASH_RADIUS := 200.0
const COMBO_HITSTOP := 0.09
# One shared impact profile for all three fusions, rather than each combo
# picking its own (Frostfire 8.0, Overload 7.0, Superconductor none at all --
# so the fusions didn't even feel consistent with each other). Sits below the
# boss entrance's 14.0 so a fusion proc still reads as smaller than a boss
# arriving.
const COMBO_SHAKE_INTENSITY := 11.0
const COMBO_SHAKE_DURATION := 0.24


static func _combo_feedback(target: Node, amount: float, color: Color, kind: String) -> void:
	# Called BEFORE the combo's take_damage so the position is still valid even
	# if that damage kills (and frees) the target.
	if not is_instance_valid(target):
		return
	var host := target.get_tree().current_scene
	if not is_instance_valid(host):
		return
	var pos: Vector2 = target.global_position
	ImpactVFX.flash_burst(pos, COMBO_FLASH_RADIUS, color, host)
	match kind:
		"frostfire":
			# (2026-07-23) Real fused art now (an ice bolt sheathed in flame),
			# replacing the generic ice_burst + fire_explosion stack that read
			# as ordinary chip damage. See ImpactVFX.frostfire_bolt().
			ImpactVFX.frostfire_bolt(pos, COMBO_FLASH_RADIUS, host)
		"superconductor":
			# (2026-07-23) Real fused art (ice crystals caged in lightning),
			# replacing the generic spark_burst + ice_shards stack.
			ImpactVFX.superconductor_arc(pos, COMBO_FLASH_RADIUS, host)
		"overload":
			# (2026-07-23) Real fused art (a fire/lightning wind-up into a
			# blast), replacing the generic explosion + spark + shockwave stack.
			# Keeps the ground shockwave, which sells the splash radius.
			ImpactVFX.overload_burst(pos, COMBO_FLASH_RADIUS, host)
			ImpactVFX.ground_shockwave(pos, OVERLOAD_SPLASH_RADIUS, host)
	DamageNumber.spawn(amount, pos, color, host, true)
	# Shake here rather than per-combo, so all three fusions land with the same
	# weight (Superconductor previously had no shake at all).
	var cam := target.get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(COMBO_SHAKE_INTENSITY, COMBO_SHAKE_DURATION)
	GameManager.hitstop(COMBO_HITSTOP)


static func _splash_nearby(target: Node, damage: float, radius: float) -> void:
	if not is_instance_valid(target):
		return
	for enemy in target.get_tree().get_nodes_in_group("enemy"):
		if enemy == target or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("take_damage"):
			continue
		if target.global_position.distance_to(enemy.global_position) <= radius:
			enemy.take_damage(damage)


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
