extends CharacterBody2D
class_name Player

const BASE_PROJECTILE_SPEED := 1000.0
# Enemies spawn around y=-40 (EnemySpawner) while AttackOrigin sits near
# y=1110 -- a freshly-spawned enemy can be ~1150px away, past
# Projectile.DEFAULT_MAX_RANGE (900). Without an explicit override here,
# every shot aimed at a still-distant "nearest enemy" (common right after a
# wave starts) expired mid-flight without ever landing.
const PLAYER_SHOT_MAX_RANGE := 1300.0
# (2026-07-16) Caps how far into the future _predict_intercept() trusts a
# zigzag enemy's instantaneous velocity.x (a sine wave, not a straight line) --
# see that function for the full reasoning. Comfortably under a quarter-period
# of the fastest zigzag_frequency currently used (Goblin Runner, 1.2Hz -> ~0.21s).
const MAX_X_LEAD_TIME := 0.25
const IDLE_BOB_AMPLITUDE := 2.5
const IDLE_BOB_DURATION := 1.1
const RECOIL_OFFSET := 12.0
const RECOIL_DURATION := 0.12
const RECOIL_SCALE_PUNCH := 1.08  # extra scale-up on top of the pull-back, scaled by _recoil_intensity_for()
const MOVEMENT_SPEED := 400.0
const MIN_X := 60.0
const MAX_X := 660.0
# (2026-07-16) 15.0->8.0 -- user playtest feedback: the multishot fan spread
# too wide, especially once "+1 Arrow" stacked the shot count up (each extra
# arrow added another full 15-degree step with no cap on the total spread).
const SPREAD_STEP_DEGREES := 8.0
# (2026-07-16) bonus_projectile_count ("+1 Arrow") stacks with no limit of
# its own onto whichever basic-line skill is active -- without a ceiling,
# enough picks could make Multishot or Piercing Arrow fire an absurd number
# of arrows in one volley. User asked for a hard cap of 6 total arrows.
const MAX_SHOT_COUNT := 6

# Arrow Rain / Burning Rain / Thunder Storm (SkillData.FireMode.ARROW_RAIN):
# telegraphed area strikes, not a literal top-to-bottom falling volley -- see
# _fire_area_strike(). Warning-circle tint per source (basic line has no
# element of its own, so it gets a neutral warm tone).
const AREA_STRIKE_COLOR_BASIC := Color(0.85, 0.7, 0.3, 0.5)
const AREA_STRIKE_COLOR_FIRE := Color(0.9, 0.25, 0.1, 0.5)
const AREA_STRIKE_COLOR_LIGHTNING := Color(0.55, 0.2, 0.85, 0.5)

const UPGRADE_POOL: Array[String] = [
	"damage", "cooldown", "projectile_count", "projectile_speed",
	"crit_chance", "hp", "xp_gain",
]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var attack_timer: Timer = $BasicShotTimer  # the one and only attack loop; see _current_skill
@onready var fire_skill_timer: Timer = $FireSkillTimer
@onready var frost_skill_timer: Timer = $FrostSkillTimer
@onready var lightning_skill_timer: Timer = $LightningSkillTimer

@export var basic_shot: SkillData
@export var multishot: SkillData
@export var piercing_arrow: SkillData
@export var trap_shot: SkillData
# Index 0/1/2/3 = tier 1/2/3/4 -- e.g. fire_skills = [Fire Arrow, Explosive
# Volley, Burning Rain, Wildfire Storm]. fire_level (1-4) indexes straight
# into this array; each tier pick wholesale-swaps the active attack,
# mirroring the basic line's own Basic Shot -> Multishot -> ... progression,
# just scoped per element. (2026-07-16) grew from 3 to 4 tiers -- see
# apply_element_upgrade() and wave_upgrade_popup.gd's _max_tier_for().
@export var fire_skills: Array[SkillData] = []
@export var frost_skills: Array[SkillData] = []
@export var lightning_skills: Array[SkillData] = []

var max_hp := 10.0  # was a const; now mutable since HP upgrades increase it. (2026-07-16) 100.0->10.0, see the "hp" upgrade case below and item/enemy-damage rescaling for the rest of this change.
var current_hp := max_hp

var level := 1
var xp := 0

var damage_mult := 1.0
var cooldown_mult := 1.0
var bonus_projectile_count := 0
var projectile_speed_mult := 1.0
var crit_chance := 0.0
var xp_gain_mult := 1.0
var fire_level := 0  # highest tier reached (0-3), not a pick count
var lightning_level := 0
var frost_level := 0
# Physical line's tier (0-6): 0 = Basic Shot (starting default, no pick
# needed), 1-3 = Multishot/Piercing Arrow/Trap Shot (each swaps the active
# skill wholesale), 4-6 = Rigged Trap/Volatile Trap/Trap Mastery, 3 stat-only
# upgrades that each extend Trap Shot's detonation a bit further rather than
# swapping in a new skill -- see apply_element_upgrade()'s PHYSICAL branch.
# Unlike elementals, physical has no "active selection": whichever tier is
# reached is always what attack_timer fires, since there's only ever one
# physical line.
# (2026-07-16) Arrow Rain (formerly tier 3) removed -- Trap Shot moved up to
# tier 3. (2026-07-16) The single tier-4 "Trap Mastery" stat jump split into 3
# progressive tiers (4-6) instead of one lump sum, per user request -- see
# physical_trap_detonate_mult below.
var physical_level := 0

# Only one elemental skill auto-fires at a time -- players can still invest
# tiers into all 3 trees (see apply_element_upgrade()), but their timers stay
# stopped unless active. -1 = no element unlocked yet. See select_active_element().
var active_element: int = -1

# Independent elemental skill damage/cooldown multipliers -- deliberately kept
# separate from the basic line's damage_mult/cooldown_mult/bonus_projectile_count
# so the two skill tracks stay fully independent (see _fire_elemental_skill()).
var fire_skill_dmg_mult := 1.0
var fire_skill_cd_mult := 1.0
var frost_skill_dmg_mult := 1.0
var frost_skill_cd_mult := 1.0
var lightning_skill_dmg_mult := 1.0
var lightning_skill_cd_mult := 1.0

# Elemental skill-tree branch stats -- see resources/upgrades/*.tres and
# StatusEffects for where each is read.
var fire_spread_chance := 0.0
var fire_dps_mult := 1.0
var fire_explode_on_death := 0.0
var fire_duration_bonus := 0.0
var frost_duration_bonus := 0.0
var frost_damage_amp := 0.0
var frost_spread_chance := 0.0
var frost_combo_bonus_mult := 0.0
var lightning_slow_bonus := 0.0
var lightning_dps := 0.0
var lightning_spread_chance := 0.0
var lightning_combo_bonus_mult := 0.0
var physical_trap_detonate_mult := 0.0  # 0 = off; accumulates across tiers 4-6 (Rigged Trap/Volatile Trap/Trap Mastery, +0.3/+0.3/+0.4); trap deals bonus damage (base_damage * this) in a wider blast on a kill or on expiry

var is_dead := false
var _current_skill: SkillData  # the single active attack; upgrades wholesale at fixed levels
var _current_fire_skill: SkillData  # null until fire_level >= 1; see _update_elemental_skill()
var _current_frost_skill: SkillData
var _current_lightning_skill: SkillData

var _sprite_base_position: Vector2
var _sprite_base_scale: Vector2
var _idle_tween: Tween
var _recoil_tween: Tween

signal hp_changed(current: float, max_hp: float)
signal xp_changed(current: int, needed: int)
signal level_up(new_level: int)
signal skill_unlocked(skill: SkillData)
# HUD-only signal: fires whenever an element's active skill is set or swaps
# tier, so HUD can relabel/track the row by element identity rather than by
# SkillData reference (which changes across tiers). Element is
# UpgradeResource.ElementType, typed int since signals can't carry a nested enum.
signal elemental_skill_changed(element: int, skill: SkillData)
# HUD-only signal: fires when the *active* element changes (first auto-activate
# on unlock, or an explicit select_active_element() pick) -- distinct from
# elemental_skill_changed, which fires on every tier pick regardless of which
# element is active.
signal active_element_switched(element: int, skill: SkillData)
signal died
signal item_collected(item: ItemData)
# Fires whenever a weapon/armor/accessory slot's contents change (equip or
# replace) -- HUD listens to keep its 3 equip-slot icons in sync. item is
# null when a slot is cleared (never happens today -- replacement is
# immediate -- but kept nullable so a future "unequip" action doesn't need a
# new signal).
signal equipment_changed(slot: String, item: ItemData)

# One item per category, replaced (not stacked) by picking up another of the
# same category -- see _equip_item(). Consumables never occupy a slot; they
# apply their effect once and are gone, same as before this system existed.
var equipped: Dictionary = {"weapon": null, "armor": null, "accessory": null}
# (2026-07-17) The exact stat delta _equip_item() actually applied for each
# occupied slot -- reverted by subtracting this measured value directly
# rather than recomputing a nominal "stacks * per-stack increment" amount,
# which could overshoot if the original apply() call had been clamped (e.g.
# cooldown_mult's 0.3 floor, crit_chance's 1.0 ceiling), permanently
# over-correcting the stat on every future equip/unequip.
var _equipped_deltas: Dictionary = {"weapon": 0.0, "armor": 0.0, "accessory": 0.0}


func _ready() -> void:
	add_to_group("player")
	_apply_meta_upgrades()
	_current_skill = basic_shot
	attack_timer.wait_time = _current_skill.cooldown
	attack_timer.timeout.connect(_on_attack_timeout)
	fire_skill_timer.timeout.connect(_on_fire_skill_timeout)
	frost_skill_timer.timeout.connect(_on_frost_skill_timeout)
	lightning_skill_timer.timeout.connect(_on_lightning_skill_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	_sprite_base_position = sprite.position
	_sprite_base_scale = sprite.scale
	sprite.play("idle")
	_start_idle_bob()


func _apply_meta_upgrades() -> void:
	# Permanent, essence-purchased bonuses from SaveManager -- applied once at
	# spawn, on top of whatever a fresh run already starts with. Same stat
	# vocabulary as apply_upgrade()'s in-run picks, just sourced from
	# meta-progression instead of a level-up/wave-clear choice.
	max_hp += SaveManager.get_meta_bonus("vitality")
	current_hp = max_hp
	damage_mult += SaveManager.get_meta_bonus("power")
	cooldown_mult = maxf(cooldown_mult - SaveManager.get_meta_bonus("quickdraw"), 0.3)
	xp_gain_mult += SaveManager.get_meta_bonus("insight")


func _physics_process(delta: float) -> void:
	if is_dead or GameManager.state in [GameManager.State.LEVEL_UP, GameManager.State.WAVE_UPGRADE, GameManager.State.PAUSED, GameManager.State.GAME_OVER]:
		return
	
	var move_dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir += 1.0
		
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse_pos := get_global_mouse_position()
		var diff := mouse_pos.x - global_position.x
		if abs(diff) > 5.0:
			move_dir = sign(diff)
			
	if move_dir != 0.0:
		velocity.x = move_dir * MOVEMENT_SPEED
	else:
		velocity.x = 0.0
		
	velocity.y = 0.0
	move_and_slide()
	global_position.x = clampf(global_position.x, MIN_X, MAX_X)


func xp_to_next_level() -> int:
	return 20 + 10 * (level - 1)


func gain_xp(amount: int) -> void:
	xp += roundi(amount * xp_gain_mult)
	xp_changed.emit(xp, xp_to_next_level())
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		_on_level_up(level)
	xp_changed.emit(xp, xp_to_next_level())


func _on_level_up(new_level: int) -> void:
	level_up.emit(new_level)
	SignalBus.level_up.emit(new_level)
	# The physical line (Multishot/Piercing Arrow/Trap Shot/Trap Mastery) no
	# longer auto-swaps at fixed levels -- it's now a wave-clear player pick
	# like the elemental trees, see apply_element_upgrade()'s PHYSICAL branch.


func apply_upgrade(upgrade_id: String) -> void:
	# (2026-07-16) Same increments for both the level-up popup and world item
	# drops -- damage +2%, cooldown -3%, projectile_speed +5%, crit_chance
	# +2%, xp_gain +5%, hp/shield +2.0 (was 10%/-8%/15%/5%/10% here; item
	# drops already used these smaller values via the now-removed
	# _apply_item_stat_boost(), this just brings the level-up popup in line
	# with it per user feedback that the popup still showed the old numbers).
	match upgrade_id:
		"damage":
			damage_mult += 0.02
		"cooldown":
			cooldown_mult = maxf(cooldown_mult - 0.03, 0.3)
		"projectile_count":
			bonus_projectile_count += 1
		"projectile_speed":
			projectile_speed_mult += 0.05
		"crit_chance":
			crit_chance = minf(crit_chance + 0.02, 1.0)
		"hp":
			# (2026-07-16) Restores HP instead of raising max_hp -- per user
			# request, a straight heal reads better than a permanent capacity
			# bump, and naturally does nothing once already at full HP via minf().
			var before_hp := current_hp
			current_hp = minf(current_hp + 2.0, max_hp)
			hp_changed.emit(current_hp, max_hp)
			if current_hp > before_hp:
				SignalBus.player_healed.emit(current_hp - before_hp)
		"xp_gain":
			xp_gain_mult += 0.05
		"max_hp":
			# Armor-only stat (never in UPGRADE_POOL, so it never appears as a
			# level-up/wave-clear pick) -- a real capacity increase rather than
			# "hp"'s one-shot heal, since gear should feel like it's worn, not
			# consumed. See _equip_item()/_revert_equip_stat().
			max_hp += 2.0
			current_hp = minf(current_hp + 2.0, max_hp)
			hp_changed.emit(current_hp, max_hp)
			SignalBus.player_healed.emit(2.0)
	_refresh_timer_cooldowns()


func apply_element_upgrade(upgrade: UpgradeResource) -> void:
	if upgrade.element == UpgradeResource.ElementType.PHYSICAL:
		physical_level += 1
		match physical_level:
			1: _current_skill = multishot
			2: _current_skill = piercing_arrow
			3: _current_skill = trap_shot
			# 4-6 have no case: Rigged Trap/Volatile Trap/Trap Mastery are all
			# stat-only upgrades (see physical_trap_detonate_mult) that each
			# extend tier 3's Trap Shot a bit further rather than swapping in
			# a new skill, so _current_skill just stays whatever tier 3 set.
		_refresh_timer_cooldowns()
		skill_unlocked.emit(_current_skill)
		SignalBus.skill_unlocked.emit(_current_skill)
		_apply_upgrade_stats(upgrade)
		return
	# tier == 0 marks the repeatable +damage/-cooldown cards (see
	# fire_damage_boost.tres etc.) -- these must not advance tree progress or
	# swap the active skill.
	if upgrade.tier >= 1:
		match upgrade.element:
			UpgradeResource.ElementType.FIRE:
				fire_level += 1
			UpgradeResource.ElementType.LIGHTNING:
				lightning_level += 1
			UpgradeResource.ElementType.FROST:
				frost_level += 1
		_update_elemental_skill(upgrade.element)
	_apply_upgrade_stats(upgrade)
	_refresh_elemental_timer(upgrade.element)


func _apply_upgrade_stats(upgrade: UpgradeResource) -> void:
	# Guarded on non-empty since e.g. all physical upgrades and every tier-1
	# root have stat_to_modify=="" -- set(upgrade.stat_to_modify, ...) would
	# resolve get("") to null and crash on null + float otherwise.
	if upgrade.stat_to_modify != "":
		set(upgrade.stat_to_modify, get(upgrade.stat_to_modify) + upgrade.modification_value)


func _update_elemental_skill(element: UpgradeResource.ElementType) -> void:
	# fire_level/frost_level/lightning_level (1-4) index straight into that
	# element's 4-tier skill array. Every tier pick -- the tier-1 root unlock
	# or a later tier-2/3/4 upgrade -- swaps the active attack wholesale: Fire
	# Arrow (T1) -> Explosive Volley (T2) -> Burning Rain (T3) -> Wildfire
	# Storm (T4), same idea per element. Only one element's Timer ever
	# actually runs (see active_element) -- a non-active element's data/tree
	# progress still updates here so it's ready the moment the player
	# switches to it, it just doesn't start firing.
	# (2026-07-17) Tier 5 (the capstone passive -- Inferno Heart/Absolute
	# Zero/Overcharge) is stat-only, same as Physical's tiers 4-6 having "no
	# case" below -- guarded here so level 5 doesn't index past the 4-entry
	# skills array; _current_*_skill just stays whatever tier 4 already set.
	match element:
		UpgradeResource.ElementType.FIRE:
			if fire_level <= fire_skills.size():
				_current_fire_skill = fire_skills[fire_level - 1]
		UpgradeResource.ElementType.FROST:
			if frost_level <= frost_skills.size():
				_current_frost_skill = frost_skills[frost_level - 1]
		UpgradeResource.ElementType.LIGHTNING:
			if lightning_level <= lightning_skills.size():
				_current_lightning_skill = lightning_skills[lightning_level - 1]
	# Refresh wait_time BEFORE start() -- Timer.start() latches whatever
	# wait_time currently holds into time_left, and a never-started Timer
	# still has Godot's default wait_time (1.0s), not the skill's real
	# cooldown. Setting wait_time after start() left the very first shot
	# firing off the stale 1.0s default instead of e.g. Fire Arrow's 1.6s.
	_refresh_elemental_timer(element)
	var skill := _current_skill_for_element(element)
	if active_element == -1:
		# First elemental unlock of the run -- auto-activate it so the player
		# isn't left with zero elemental damage until they manually select one.
		select_active_element(element)
	elif element == active_element:
		var timer := get_elemental_timer_by_element(element)
		if timer.is_stopped():
			timer.start()
	skill_unlocked.emit(skill)
	SignalBus.skill_unlocked.emit(skill)
	elemental_skill_changed.emit(element, skill)


func _current_skill_for_element(element: int) -> SkillData:
	match element:
		UpgradeResource.ElementType.FIRE:
			return _current_fire_skill
		UpgradeResource.ElementType.FROST:
			return _current_frost_skill
		UpgradeResource.ElementType.LIGHTNING:
			return _current_lightning_skill
	return null


func get_physical_tier() -> int:
	return physical_level


func get_element_tier(element: int) -> int:
	match element:
		UpgradeResource.ElementType.FIRE:
			return fire_level
		UpgradeResource.ElementType.FROST:
			return frost_level
		UpgradeResource.ElementType.LIGHTNING:
			return lightning_level
	return 0


func get_current_physical_skill() -> SkillData:
	return _current_skill


func get_current_skill_for_element(element: int) -> SkillData:
	return _current_skill_for_element(element)


func select_active_element(element: int) -> void:
	# Called directly by the HUD when the player taps a specific unlocked
	# element's icon -- picks that exact element rather than cycling, so
	# there's no ambiguity about which path becomes active (a blind
	# next-in-list cycle was confusing once 3 elements were unlocked: tapping
	# it didn't reliably return to the path the player expected).
	if element == active_element:
		return
	if _current_skill_for_element(element) == null:
		return  # not actually unlocked yet -- ignore rather than activate a blank skill
	var old_timer := get_elemental_timer_by_element(active_element)
	if is_instance_valid(old_timer):
		old_timer.stop()
	active_element = element
	_refresh_elemental_timer(element)
	get_elemental_timer_by_element(element).start()
	active_element_switched.emit(element, _current_skill_for_element(element))


func _refresh_elemental_timer(element: int) -> void:
	# Recomputes the given element's Timer.wait_time from whichever tier is
	# currently active -- covers both "just unlocked/tiered up" and "picked a
	# later cooldown-reduction card" with one code path.
	match element:
		UpgradeResource.ElementType.FIRE:
			if _current_fire_skill != null:
				fire_skill_timer.wait_time = _current_fire_skill.cooldown * maxf(fire_skill_cd_mult, 0.3)
		UpgradeResource.ElementType.FROST:
			if _current_frost_skill != null:
				frost_skill_timer.wait_time = _current_frost_skill.cooldown * maxf(frost_skill_cd_mult, 0.3)
		UpgradeResource.ElementType.LIGHTNING:
			if _current_lightning_skill != null:
				lightning_skill_timer.wait_time = _current_lightning_skill.cooldown * maxf(lightning_skill_cd_mult, 0.3)


func get_elemental_timer_by_element(element: int) -> Timer:
	match element:
		UpgradeResource.ElementType.FIRE:
			return fire_skill_timer
		UpgradeResource.ElementType.FROST:
			return frost_skill_timer
		UpgradeResource.ElementType.LIGHTNING:
			return lightning_skill_timer
	return null


func _on_fire_skill_timeout() -> void:
	_fire_elemental_skill(_current_fire_skill, StatusEffects.FIRE, fire_skill_dmg_mult, StatusEffects.FIRE_DURATION + fire_duration_bonus)


func _on_frost_skill_timeout() -> void:
	_fire_elemental_skill(_current_frost_skill, StatusEffects.FROST, frost_skill_dmg_mult, StatusEffects.FROST_DURATION + frost_duration_bonus)


func _on_lightning_skill_timeout() -> void:
	_fire_elemental_skill(_current_lightning_skill, StatusEffects.LIGHTNING, lightning_skill_dmg_mult, StatusEffects.LIGHTNING_DURATION)


func _fire_elemental_skill(skill: SkillData, element: String, dmg_mult: float, duration: float) -> void:
	if skill == null:
		return
	# chance: 1.0 -- an elemental skill's own hit always applies its status,
	# unlike the basic line which carries no status at all (see _fire_at()).
	var status_rolls: Array[Dictionary] = [{"element": element, "chance": 1.0, "duration": duration}]
	if skill.fire_mode == SkillData.FireMode.ARROW_RAIN:
		_fire_elemental_rain(skill, dmg_mult, status_rolls)
	else:
		_fire_elemental_projectile(skill, dmg_mult, status_rolls)
	_stop_idle_bob()
	_play_recoil(_recoil_intensity_for(skill))
	if sprite.animation != "attack":
		sprite.play("attack")
	SignalBus.player_shot.emit()


func _fire_elemental_projectile(skill: SkillData, dmg_mult: float, status_rolls: Array[Dictionary]) -> void:
	# Handles both single-target tiers (Fire Arrow/Ice Shot/Volt Arrow,
	# projectile_count=1) and the multi-arrow tier-2 spread (Explosive Volley,
	# projectile_count=3) -- burst_radius/chain_count (Frozen Burst, Ice Wall
	# Nova, Chain Spark) ride along on the projectile itself, applied at hit
	# time in Projectile._on_body_entered(). All shots fire as a fixed cone
	# around one aim direction (see _spread_offset()) rather than each arrow
	# separately retargeting its own nearest enemy.
	var shot_count: int = skill.projectile_count
	var targets := _get_nearest_enemies(1)
	if targets.is_empty():
		return
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	var aim_point := _predict_intercept(attack_origin.global_position, targets[0], proj_speed)
	var base_dir := (aim_point - attack_origin.global_position).normalized()
	for i in shot_count:
		var dir := base_dir.rotated(_spread_offset(i, shot_count))
		var dmg := skill.base_damage * dmg_mult * (2.0 if randf() < crit_chance else 1.0)
		var proj: Projectile = pool.acquire(skill.projectile_scene)
		# Only the dead-center shot (i==0) homes and is guaranteed to connect --
		# the fanned side shots (tier-2's 3-arrow spread) keep their fixed
		# trajectory, same bonus-AOE role they've always had, so multishot still
		# reads as a fan rather than every arrow collapsing onto one target.
		var homing_target: Node2D = targets[0] if i == 0 else null
		proj.activate(dir, proj_speed, dmg, attack_origin.global_position, skill.pierce_count, "enemy", PLAYER_SHOT_MAX_RANGE, status_rolls, skill.burst_radius, skill.chain_count, skill.visual_scale, skill.burst_vfx_id, homing_target)


func _fire_elemental_rain(skill: SkillData, dmg_mult: float, status_rolls: Array[Dictionary]) -> void:
	# Burning Rain / Thunder Storm (tier 3): a telegraphed area strike, same
	# as the basic line's Arrow Rain -- see _fire_area_strike().
	var color := AREA_STRIKE_COLOR_LIGHTNING
	if not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.FIRE:
		color = AREA_STRIKE_COLOR_FIRE
	_fire_area_strike(skill, dmg_mult, status_rolls, color)


func _refresh_timer_cooldowns() -> void:
	attack_timer.wait_time = _current_skill.cooldown * cooldown_mult


func _on_attack_timeout() -> void:
	_auto_fire(_current_skill)


func _auto_fire(skill: SkillData) -> void:
	match skill.fire_mode:
		SkillData.FireMode.ARROW_RAIN:
			_fire_arrow_rain(skill)
		SkillData.FireMode.TRAP_SHOT:
			if not _fire_trap_shot(skill):
				return
		_:
			# Fixed cone around the nearest enemy's direction, same shot
			# count regardless of how many distinct targets are actually
			# nearby -- previously each arrow independently retargeted its
			# own nearest enemy, which read as erratic once the player could
			# strafe left/right instead of staying fixed at the bottom.
			var shot_count: int = mini(skill.projectile_count + bonus_projectile_count, MAX_SHOT_COUNT)
			var targets := _get_nearest_enemies(1)
			if targets.is_empty():
				return
			for i in shot_count:
				_fire_at(targets[0], skill, _spread_offset(i, shot_count))
	_stop_idle_bob()
	_play_recoil(_recoil_intensity_for(skill))
	if sprite.animation != "attack":
		sprite.play("attack")
	SignalBus.player_shot.emit()


func _start_idle_bob() -> void:
	if _idle_tween:
		_idle_tween.kill()
	sprite.position = _sprite_base_position
	_idle_tween = create_tween()
	_idle_tween.set_loops()
	_idle_tween.tween_property(sprite, "position:y", _sprite_base_position.y - IDLE_BOB_AMPLITUDE, IDLE_BOB_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(sprite, "position:y", _sprite_base_position.y + IDLE_BOB_AMPLITUDE, IDLE_BOB_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_idle_bob() -> void:
	if _idle_tween:
		_idle_tween.kill()
		_idle_tween = null
	sprite.position = _sprite_base_position


func _play_recoil(intensity: float = 1.0) -> void:
	# With multiple skills able to fire in the same or adjacent frames, killing
	# and restarting this tween on every single shot made overlapping fires
	# visually stutter -- let an in-progress recoil finish instead of resetting.
	if _recoil_tween and _recoil_tween.is_running():
		return
	sprite.position.x = _sprite_base_position.x
	sprite.scale = _sprite_base_scale
	var offset := RECOIL_OFFSET * intensity
	var punch := 1.0 + (RECOIL_SCALE_PUNCH - 1.0) * intensity
	_recoil_tween = create_tween()
	_recoil_tween.set_parallel(true)
	_recoil_tween.tween_property(sprite, "position:x", _sprite_base_position.x - offset, RECOIL_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(sprite, "scale", _sprite_base_scale * punch, RECOIL_DURATION * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.chain().set_parallel(true)
	_recoil_tween.tween_property(sprite, "position:x", _sprite_base_position.x, RECOIL_DURATION * 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_recoil_tween.tween_property(sprite, "scale", _sprite_base_scale, RECOIL_DURATION * 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _recoil_intensity_for(skill: SkillData) -> float:
	# Heavier skills get a bigger kick, matching the plan docs' "heavier
	# skills feel heavier" guidance without needing new sprite frames.
	if skill.fire_mode == SkillData.FireMode.ARROW_RAIN:
		return 1.5
	if skill.fire_mode == SkillData.FireMode.TRAP_SHOT:
		return 1.2
	if skill.projectile_count > 1:
		return 1.25
	return 1.0


func _get_nearest_enemies(count: int) -> Array[Node2D]:
	var enemies: Array[Node2D] = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			enemies.append(enemy)
	enemies.sort_custom(func(a, b): return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b.global_position))
	if enemies.size() > count:
		enemies.resize(count)
	return enemies


func _fire_arrow_rain(skill: SkillData) -> void:
	# Basic-line Arrow Rain: a telegraphed area strike (see _fire_area_strike),
	# not a literal top-to-bottom falling volley. Carries no status (the basic
	# line never does) and, unlike the elemental rain skills, its zone count
	# scales with bonus_projectile_count ("+1 Arrow" still means "more zones").
	_fire_area_strike(skill, damage_mult, [], AREA_STRIKE_COLOR_BASIC, bonus_projectile_count)


func _fire_area_strike(skill: SkillData, dmg_mult: float, status_rolls: Array[Dictionary], telegraph_color: Color, bonus_zones: int = 0) -> void:
	# Scatters impact zones near real enemies (falling back to the general
	# engagement area above the player if none are in range), shows a warning
	# circle on each, then guarantee-hits everything caught inside once the
	# telegraph resolves -- matches the plan docs' "warning marker -> impact"
	# framing and reuses boss_base.gd's own telegraphed-zone pattern.
	var zone_count: int = skill.rain_arrow_count + bonus_zones
	var scatter: float = skill.rain_spread_width
	var radius: float = skill.trap_radius
	# Burning Rain and Thunder Storm each get their own falling/impact art
	# instead of the plain procedural circle basic Arrow Rain still uses.
	var is_fire = not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.FIRE
	var is_lightning = not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.LIGHTNING
	var targets := _get_nearest_enemies(zone_count)
	var points: Array[Vector2] = []
	if targets.is_empty():
		for _i in zone_count:
			points.append(global_position + Vector2(randf_range(-scatter, scatter) / 2.0, -randf_range(150.0, 500.0)))
	else:
		for _i in zone_count:
			var anchor: Vector2 = targets[randi() % targets.size()].global_position
			points.append(anchor + Vector2(randf_range(-scatter, scatter) / 2.0, randf_range(-scatter, scatter) / 2.0))
	for p in points:
		Telegraph.show_circle(p, radius, telegraph_color, skill.telegraph_time, self)
		if is_fire:
			ImpactVFX.fire_meteor_fall(p, skill.telegraph_time, self)
		elif is_lightning:
			ImpactVFX.lightning_strike_fall(p, skill.telegraph_time, self)
		else:
			ImpactVFX.arrow_rain_fall(p, skill.telegraph_time, self)
	await get_tree().create_timer(skill.telegraph_time, false).timeout
	if not is_instance_valid(self):
		return
	var dmg := skill.base_damage * dmg_mult * (2.0 if randf() < crit_chance else 1.0)
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(7.0, 0.18)
	for p in points:
		if is_fire:
			ImpactVFX.fire_explosion(p, radius, self)
		elif is_lightning:
			ImpactVFX.spark_burst(p, radius, self)
		else:
			ImpactVFX.arrow_rain_impact(p, radius, self)
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
				continue
			if enemy.global_position.distance_to(p) > radius:
				continue
			enemy.take_damage(dmg)
			if enemy.has_method("apply_status"):
				for roll in status_rolls:
					if randf() < roll["chance"]:
						enemy.apply_status(roll["element"], roll["duration"])


func _fire_trap_shot(skill: SkillData) -> bool:
	if skill.trap_scene == null:
		return false
	var targets := _get_nearest_enemies(1)
	if targets.is_empty():
		return false
	var target: Node2D = targets[0]
	var trap = skill.trap_scene.instantiate()
	var dmg := skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	# A bare `[]` literal here fails TrapZone.activate()'s typed Array[Dictionary]
	# param at the call boundary (confirmed via a headless repro -- GDScript
	# doesn't coerce an untyped empty-array literal across a typed-array
	# parameter the way it does for the function's own default value) -- must
	# be a real typed local instead.
	var no_status_rolls: Array[Dictionary] = []
	trap.activate(dmg, skill.trap_duration, skill.trap_radius, target.global_position, no_status_rolls, physical_trap_detonate_mult)
	get_tree().current_scene.add_child(trap)
	return true


func _spread_offset(i: int, shot_count: int) -> float:
	# Shot 0 is always the guaranteed dead-center hit on the real target;
	# the rest fan outward in alternating +/- SPREAD_STEP_DEGREES steps:
	# [0, +8, -8, +16, -16, ...]. A purely symmetric spread (an earlier
	# approach) has no exact center shot whenever shot_count is even -- e.g.
	# 4 shots would land at +/-7.5/+/-22.5 degrees (back when the step was
	# 15), so every single arrow misses a stationary target dead ahead.
	# Since bonus_projectile_count ("+1 Arrow") can turn Multishot's odd base
	# count into an even one, this isn't an edge case; it needs to hold for
	# every shot_count.
	if i == 0:
		return 0.0
	var step := (i + 1) / 2
	var sign := 1.0 if i % 2 == 1 else -1.0
	return deg_to_rad(SPREAD_STEP_DEGREES * step * sign)


func _fire_at(target: Node2D, skill: SkillData, angle_offset: float = 0.0) -> void:
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult
	var aim_point := _predict_intercept(attack_origin.global_position, target, proj_speed)
	var dir := (aim_point - attack_origin.global_position).normalized().rotated(angle_offset)
	var dmg := skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	var proj = pool.acquire(skill.projectile_scene)
	proj.activate(dir, proj_speed, dmg, attack_origin.global_position, skill.pierce_count, "enemy", PLAYER_SHOT_MAX_RANGE)


func _predict_intercept(from: Vector2, target: Node2D, proj_speed: float) -> Vector2:
	# Enemies keep falling while the shot is in flight, so aiming at their
	# current position alone would systematically miss (arrows travel far
	# slower relative to fall speed than it looks at a glance). Since
	# proj_speed is much greater than any enemy's speed, a couple of
	# fixed-point passes converges to a good intercept point without a full
	# quadratic solve.
	var target_vel: Vector2 = target.velocity if "velocity" in target else Vector2.ZERO
	var predicted := target.global_position
	for _i in 4:
		var travel_time := from.distance_to(predicted) / proj_speed
		# Vertical velocity is constant for an enemy's whole lifetime (see
		# straight/dive/zigzag movement behaviors -- only zigzag ever touches
		# velocity.x, every frame), so a full linear lead is accurate no
		# matter how long the shot is in flight. Horizontal velocity is only
		# ever non-zero for zigzag movement, which OSCILLATES (a sine wave)
		# rather than moving in a straight line -- extrapolating an
		# instantaneous zigzag velocity.x linearly across a long flight time
		# (freshly-spawned enemies can be ~1100px away, ~1.1s of flight)
		# overshoots wildly once the real enemy has curved back the other
		# way. Capping how far into the future the X lead is trusted fixed a
		# measured hit-rate collapse (32%, in a throwaway headless test
		# against a realistic zigzag enemy at spawn range) without changing
		# the already-accurate close-range case at all.
		var x_lead_time := minf(travel_time, MAX_X_LEAD_TIME)
		predicted = target.global_position + Vector2(target_vel.x * x_lead_time, target_vel.y * travel_time)
	return predicted


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		sprite.play("idle")
		_start_idle_bob()


func take_damage(amount: float) -> void:
	current_hp = maxf(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	SignalBus.player_damaged.emit(amount)
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(6.0, 0.18)
	if current_hp <= 0.0 and not is_dead:
		is_dead = true
		died.emit()
		SignalBus.player_died.emit()


# (2026-07-16) A loss condition that isn't damage-based -- an advancing boss
# (Corrupted Forest Guardian) reaching its lose line calls this directly
# instead of dealing lethal damage, so GameOverScreen (which only listens for
# the `died` signal) doesn't need its own separate "boss reached the bottom"
# path.
func force_defeat() -> void:
	if is_dead:
		return
	current_hp = 0.0
	hp_changed.emit(current_hp, max_hp)
	is_dead = true
	died.emit()
	SignalBus.player_died.emit()


func apply_item(item: ItemData) -> void:
	if item.category in ["weapon", "armor", "accessory"]:
		_equip_item(item)
	else:
		match item.effect_type:
			"stat_boost":
				for _i in item.upgrade_stacks:
					apply_upgrade(item.upgrade_id)
			"instant_heal":
				var before_hp := current_hp
				current_hp = minf(current_hp + item.effect_amount, max_hp)
				hp_changed.emit(current_hp, max_hp)
				if current_hp > before_hp:
					SignalBus.player_healed.emit(current_hp - before_hp)
			"instant_bomb":
				for enemy in get_tree().get_nodes_in_group("enemy"):
					if is_instance_valid(enemy) and enemy.has_method("take_damage"):
						enemy.take_damage(item.effect_amount)
			"instant_xp":
				gain_xp(int(item.effect_amount))
	item_collected.emit(item)
	SignalBus.item_collected.emit(item.id, item.rarity)


func _equip_item(item: ItemData) -> void:
	# Real gear, not a one-shot pickup: only ever ONE item per slot at a time.
	# Picking up a 2nd weapon replaces the 1st, reverting its stat exactly so
	# swapping gear never silently stacks bonuses from items no longer held.
	var slot: String = item.category
	var previous: ItemData = equipped[slot]
	if previous != null:
		_revert_equip_stat(previous.upgrade_id, _equipped_deltas[slot])
	var before := _get_equip_stat_value(item.upgrade_id)
	for _i in item.upgrade_stacks:
		apply_upgrade(item.upgrade_id)
	_equipped_deltas[slot] = _get_equip_stat_value(item.upgrade_id) - before
	equipped[slot] = item
	equipment_changed.emit(slot, item)


func _get_equip_stat_value(upgrade_id: String) -> float:
	match upgrade_id:
		"damage":
			return damage_mult
		"cooldown":
			return cooldown_mult
		"projectile_count":
			return float(bonus_projectile_count)
		"projectile_speed":
			return projectile_speed_mult
		"crit_chance":
			return crit_chance
		"xp_gain":
			return xp_gain_mult
		"max_hp":
			return max_hp
	return 0.0


func _revert_equip_stat(upgrade_id: String, delta: float) -> void:
	# Subtracts the exact delta _equip_item() measured actually happened
	# (before/after, via _get_equip_stat_value()), not a nominal
	# "stacks * per-stack increment" recomputation -- if the original apply
	# was clamped (e.g. cooldown_mult's 0.3 floor, crit_chance's 1.0
	# ceiling), the measured delta already reflects that, so this can never
	# overshoot and permanently over-correct the stat on un-equip.
	match upgrade_id:
		"damage":
			damage_mult -= delta
		"cooldown":
			cooldown_mult -= delta
			_refresh_timer_cooldowns()
		"projectile_count":
			bonus_projectile_count -= roundi(delta)
		"projectile_speed":
			projectile_speed_mult -= delta
		"crit_chance":
			crit_chance -= delta
		"xp_gain":
			xp_gain_mult -= delta
		"max_hp":
			max_hp -= delta
			current_hp = minf(current_hp, max_hp)
			hp_changed.emit(current_hp, max_hp)
