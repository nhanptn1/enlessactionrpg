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
# (2026-07-21) Dash/dodge: a quick burst covering ~162px (900 * 0.18) --
# comfortably clears every boss zone-attack radius in the game (Throw Rock 34,
# Arrow Rain 42, Leap Smash 60) in one dash. Player is fully invulnerable for
# the dash's own duration (see _is_invulnerable in take_damage()), so it reads
# as a real dodge through danger, not just a fast reposition. Explicitly
# floated in plan/gameplay-character-plan.txt ("optional dash or dodge can be
# added later") and considered but not picked for Phase 3; picked as the
# start of the next phase per direct user choice.
const DASH_SPEED := 900.0
const DASH_DURATION := 0.18
const DASH_COOLDOWN := 1.8
const DASH_ALPHA_DIP := 0.4  # visual-only cue that i-frames are active, no new art needed

# (2026-07-21) Phase 4 pillar 2: late-run ultimate ability. (2026-07-22)
# Unlocked the moment the ACTIVE element reaches ULTIMATE_UNLOCK_TIER (4, the
# last active-skill tier -- what players read as "maxed"). Was tier 5 (the
# capstone) but that was too deep to reach in most runs, so the ultimate felt
# permanently locked -- user report. Still keyed off the active element's
# *_level, so switching to a less-invested element re-locks it;
# charged by kills (any source -- SignalBus.enemy_died is emitted at the
# single death choke point, so trap/burst/chain/DOT kills all count), then
# unleashed manually with Q: a screen-wide hit on every enemy in the "enemy"
# group (bosses included -- they're in that group too, and Shielded's own
# invulnerability window still blocks it via take_damage()'s guard, which is
# correct). Each element's ultimate carries its own identity: Fire burns
# everything, Frost freezes everything, Lightning shocks everything -- the
# guaranteed status is the real payoff, feeding spreads/combos/capstones.
const ULTIMATE_UNLOCK_TIER := 4  # active element's tier that unlocks the ultimate (below CAPSTONE_TIER 5 on purpose -- see header)
# (2026-07-22) Tier each of TWO element lines must reach to fuse them. Lowered
# 5 -> 4 alongside the ultimate: requiring the tier-5 capstone on two separate
# lines was strictly harder than the ultimate gate the user already reported as
# unreachable, so fusions would essentially never fire. At tier 4 the combos
# land at base damage; pushing either line on to its tier-5 capstone then
# doubles that combo's damage -- a natural two-stage payoff.
const FUSION_UNLOCK_TIER := 4
const ULTIMATE_KILLS_REQUIRED := 40
const ULTIMATE_FIRE_DAMAGE := 30.0
const ULTIMATE_FROST_DAMAGE := 15.0  # lowest raw hit -- a full-screen freeze is already the strongest control effect in the game
const ULTIMATE_LIGHTNING_DAMAGE := 25.0
const ULTIMATE_FROST_FREEZE_DURATION := 2.5  # vs. FROST_DURATION 1.6 -- an ultimate freeze should outlast a regular one
const ULTIMATE_SHAKE_INTENSITY := 12.0
const ULTIMATE_SHAKE_DURATION := 0.35
# (2026-07-16) 15.0->8.0 -- user playtest feedback: the fan spread too wide,
# especially once "+1 Arrow" stacked the shot count up (each extra arrow added
# another full 15-degree step with no cap on the total spread).
# (2026-07-24) That fan used to come from the Multishot tier as well; with it
# removed, "+1 Arrow" is the only thing that widens a shot into one.
const SPREAD_STEP_DEGREES := 8.0
# (2026-07-16) bonus_projectile_count ("+1 Arrow") stacks with no limit of
# its own onto whichever basic-line skill is active -- without a ceiling,
# enough picks could make the active skill fire an absurd number of arrows in
# one volley. User asked for a hard cap of 6 total arrows.
const MAX_SHOT_COUNT := 6
# (2026-07-24) "+1 Chain" cap, per user: "max 4 enemy". Read as 4 nearby
# enemies receiving the chained damage, i.e. it reaches at most 4 beyond the one
# actually struck. Capped for the same reason MAX_SHOT_COUNT is -- an uncapped
# repeatable eventually stops meaning anything, and LevelUpPopup stops offering
# the card once this is reached so it never becomes a dead pick.
const MAX_CHAIN_COUNT := 4

# Arrow Rain / Burning Rain / Thunder Storm (SkillData.FireMode.ARROW_RAIN):
# telegraphed area strikes, not a literal top-to-bottom falling volley -- see
# _fire_area_strike(). Warning-circle tint per source (basic line has no
# element of its own, so it gets a neutral warm tone).
const AREA_STRIKE_COLOR_BASIC := Color(0.85, 0.7, 0.3, 0.5)
const AREA_STRIKE_COLOR_FIRE := Color(0.9, 0.25, 0.1, 0.5)
const AREA_STRIKE_COLOR_LIGHTNING := Color(0.55, 0.2, 0.85, 0.5)

const UPGRADE_POOL: Array[String] = [
	"damage", "cooldown", "projectile_count", "projectile_speed",
	"crit_chance", "hp", "xp_gain", "chain",
]

# (2026-07-24) Named because the level-up popup has to consult them to know when
# a pick would do nothing (see LevelUpPopup._eligible_upgrade_ids()). They were
# a bare 0.3 / 1.0 repeated across five call sites; re-typing either number into
# a UI file is exactly how a cap and the filter that depends on it drift apart.
const COOLDOWN_MULT_FLOOR := 0.3
const CRIT_CHANCE_MAX := 1.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var attack_timer: Timer = $BasicShotTimer  # the one and only attack loop; see _current_skill
@onready var fire_skill_timer: Timer = $FireSkillTimer
@onready var frost_skill_timer: Timer = $FrostSkillTimer
@onready var lightning_skill_timer: Timer = $LightningSkillTimer
@onready var class_skill_timer: Timer = $ClassSkillTimer  # the class skill line's own auto-fire loop, mirroring the elemental timers

@export var basic_shot: SkillData
@export var piercing_arrow: SkillData
@export var chain_arrow: SkillData
# Index 0/1/2/3 = tier 1/2/3/4 -- e.g. fire_skills = [Fire Arrow, Explosive
# Volley, Burning Rain, Wildfire Storm]. fire_level (1-4) indexes straight
# into this array; each tier pick wholesale-swaps the active attack,
# mirroring the basic line's own Basic Shot -> Piercing Arrow -> Chain Arrow
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
var bonus_chain_count := 0  # "+1 Chain" picks; see effective_chain_count()
var projectile_speed_mult := 1.0
var crit_chance := 0.0
var xp_gain_mult := 1.0
var active_run_modifier_id: String = ""  # set once in _apply_run_modifier() -- see RunModifiers.MODIFIERS
var active_class_id: String = "ranger"  # set once by ClassSelectPopup at run start via apply_class() -- see CharacterClasses.CLASSES
var class_skill_level := 0  # class skill tree tier reached (0-3) -- see apply_element_upgrade()'s CLASS branch
var fire_level := 0  # highest tier reached (0-3), not a pick count
var lightning_level := 0
var frost_level := 0
# Physical line's tier (0-5): 0 = Basic Shot (starting default, no pick
# needed), 1-2 = Piercing Arrow/Trap Shot (each swaps the active skill
# wholesale), 3-5 = Rigged Trap/Volatile Trap/Trap Mastery, 3 stat-only
# upgrades that each extend Trap Shot's detonation a bit further rather than
# swapping in a new skill -- see apply_element_upgrade()'s PHYSICAL branch.
# (2026-07-24) Was 0-6 with Multishot at tier 1; removed, see that branch.
# Unlike elementals, physical has no "active selection": whichever tier is
# reached is always what attack_timer fires, since there's only ever one
# physical line.
# (2026-07-16) Arrow Rain (formerly tier 3) removed -- Trap Shot moved up to
# tier 3. (2026-07-16) The single tier-4 "Trap Mastery" stat jump split into 3
# progressive tiers (4-6) instead of one lump sum, per user request -- see
# trap_detonate_mult below.
var physical_level := 0

# Per-run pick counts for repeatable tier-0 stat cards (upgrade id -> times
# picked). Lets the wave picker stop offering a card once it hits the
# resource's max_stacks, so a fully-maxed line (skill tier maxed AND every
# stat card capped) drops out of the picker entirely. Not persisted -- resets
# each run with the player.
var repeatable_stacks: Dictionary = {}

# (2026-07-22) Unlocked late-game elemental fusions (ElementFusions pair ids,
# e.g. "fire_frost"). Auto-unlocked when two element lines both reach max tier
# -- see _maybe_unlock_fusions(). While a fusion is active, the player's
# attacks also apply the partner element's status (see StatusEffects.apply()),
# so the pair's combo fires reliably. Per-run, not persisted.
var active_fusions: Array[String] = []
# (2026-07-23) Which fusion is currently EQUIPPED, "" = none. A fusion is no
# longer an automatic passive: unlocking it only makes it selectable, and the
# player taps its HUD row to activate it. Doing so REPLACES the active element
# -- you fire the fused projectile instead of fire/frost/lightning -- so it's a
# real choice with a tradeoff rather than free extra damage.
var active_fusion_id: String = ""
var _current_fusion_skill: SkillData
# Fusion's own upgrade stats, fed by the fusion upgrade cards that unlock once
# BOTH parent lines are fully maxed (skill tier + every stat card).
var fusion_dmg_mult := 1.0
var fusion_cd_mult := 1.0
var fusion_projectile_speed_mult := 1.0
var fusion_skill_timer: Timer  # created in _ready(), see there

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
var trap_detonate_mult := 0.0  # 0 = off; accumulates across tiers 3-5 (Rigged Trap/Volatile Trap/Trap Mastery, +0.3/+0.3/+0.4); trap deals bonus damage (base_damage * this) in a wider blast on a kill or on expiry

var is_dead := false
# (2026-07-21) Continue/revive: the player can get back up twice per run --
# the 1st time free, the 2nd time for essence (see ContinuePopup). A 3rd death
# is the real game over. Reset every run since a restart reloads the scene.
const MAX_CONTINUES := 2
const REVIVE_INVULN_TIME := 3.0  # breathing room after a revive so you don't instantly die again
var continues_used := 0
var _run_over := false  # guards the final game-over signal against a double fire
var _revive_invuln := false  # separate from _is_invulnerable (dash) so a dash ending can't clear revive i-frames
var _current_skill: SkillData  # the single active attack; upgrades wholesale at fixed levels
var _current_class_skill: SkillData  # null until class_skill_level >= 1; the active class-line skill
var _current_fire_skill: SkillData  # null until fire_level >= 1; see _update_elemental_skill()
var _current_frost_skill: SkillData
var _current_lightning_skill: SkillData

var _sprite_base_position: Vector2
var _sprite_base_scale: Vector2
var _idle_tween: Tween
var _recoil_tween: Tween
var _dash_tween: Tween
var _is_dashing := false
var _is_invulnerable := false
var _dash_time_remaining := 0.0
var _dash_cooldown_remaining := 0.0
var _last_move_dir := 1.0  # dash direction when stationary -- defaults facing right
var _dash_key_was_down := false  # manual edge-detection, matching this file's raw is_key_pressed() polling convention rather than a new Input Map action
var ultimate_charge := 0  # kills accumulated toward ULTIMATE_KILLS_REQUIRED -- public so HUD can poll it, same as attack_timer
var _ult_key_was_down := false  # same manual edge-detection as _dash_key_was_down above

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
# HUD-only signal: fires on every class-skill tier pick (see the CLASS branch
# of apply_element_upgrade()). Distinct from skill_unlocked, which the HUD
# routes to the basic-line label -- the class line gets its own top-left row.
signal class_skill_changed(skill: SkillData)
# (2026-07-22) Fires once when a late-game elemental fusion unlocks (two
# element lines both hit max tier). Also mirrored onto SignalBus so the HUD
# toast doesn't need a direct player reference. See _maybe_unlock_fusions().
signal fusion_unlocked(pair_id: String, display_name: String)
# (2026-07-23) Fires when a fusion is equipped or un-equipped ("" = none), so
# the HUD can light the active fusion row and dim the elemental ones.
signal active_fusion_changed(pair_id: String, skill: SkillData)
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
	_apply_run_modifier()
	_current_skill = basic_shot
	attack_timer.wait_time = _current_skill.cooldown
	attack_timer.timeout.connect(_on_attack_timeout)
	fire_skill_timer.timeout.connect(_on_fire_skill_timeout)
	frost_skill_timer.timeout.connect(_on_frost_skill_timeout)
	lightning_skill_timer.timeout.connect(_on_lightning_skill_timeout)
	class_skill_timer.timeout.connect(_on_class_skill_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	SignalBus.enemy_died.connect(_on_enemy_died_charge_ultimate)
	# Fusion's own auto-fire loop, built in code rather than added to
	# Player.tscn -- it mirrors the elemental timers exactly and only ever runs
	# while a fusion is equipped.
	fusion_skill_timer = Timer.new()
	fusion_skill_timer.name = "FusionSkillTimer"
	fusion_skill_timer.one_shot = false
	fusion_skill_timer.timeout.connect(_on_fusion_skill_timeout)
	add_child(fusion_skill_timer)
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
	cooldown_mult = maxf(cooldown_mult - SaveManager.get_meta_bonus("quickdraw"), COOLDOWN_MULT_FLOOR)
	xp_gain_mult += SaveManager.get_meta_bonus("insight")


# (2026-07-17) Phase 3 pillar 3: exactly one random modifier is active every
# run (see RunModifiers.MODIFIERS) -- applied after meta upgrades so it
# multiplies the meta-boosted baseline, not the raw starting stats.
# enemy_hp_mult/enemy_count_mult (Bounty Hunter/Swarm Warning) aren't applied
# here -- wave_manager.gd reads active_run_modifier_id directly since it owns
# that scaling, same pattern StatusEffects already uses to consult the player
# rather than the player pushing values into every other system.
func _apply_run_modifier() -> void:
	active_run_modifier_id = RunModifiers.roll_random_id()
	damage_mult *= RunModifiers.get_mult(active_run_modifier_id, "player_damage_mult")
	cooldown_mult = maxf(cooldown_mult * RunModifiers.get_mult(active_run_modifier_id, "player_cooldown_mult"), COOLDOWN_MULT_FLOOR)
	max_hp *= RunModifiers.get_mult(active_run_modifier_id, "player_max_hp_mult")
	current_hp = max_hp
	xp_gain_mult *= RunModifiers.get_mult(active_run_modifier_id, "player_xp_gain_mult")


# Called once by ClassSelectPopup after the player picks -- runs AFTER
# _ready()'s meta/run-modifier application (the popup can't exist before the
# player does), so class multipliers compose onto that baseline the same way
# the run modifier composes onto meta bonuses. Ranger's entry has no stat
# keys, so picking it is a true no-op beyond recording the id.
func apply_class(class_id: String) -> void:
	if not CharacterClasses.CLASSES.has(class_id):
		return
	active_class_id = class_id
	crit_chance = clampf(crit_chance + CharacterClasses.get_value(class_id, "crit_chance_bonus", 0.0), 0.0, 1.0)
	projectile_speed_mult *= CharacterClasses.get_value(class_id, "projectile_speed_mult")
	damage_mult *= CharacterClasses.get_value(class_id, "physical_dmg_mult")
	# (2026-07-24) Added for the Trapper's "harder hits, slower attacks" trade.
	# Every other class stat key was already read here, so declaring a
	# cooldown_mult in CLASSES without this would have been silently inert --
	# the exact dead-value class of bug entries 98-99 were about. Floored like
	# every other cooldown path so a future class can't stall attacks entirely.
	cooldown_mult = maxf(cooldown_mult * CharacterClasses.get_value(class_id, "cooldown_mult"), COOLDOWN_MULT_FLOOR)
	var elemental_mult := CharacterClasses.get_value(class_id, "elemental_dmg_mult")
	fire_skill_dmg_mult *= elemental_mult
	frost_skill_dmg_mult *= elemental_mult
	lightning_skill_dmg_mult *= elemental_mult
	max_hp *= CharacterClasses.get_value(class_id, "max_hp_mult")
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	# Class-colored tint on the shared archer art -- the same technique
	# elites/mutations/affinities already use, per the "tint first, real
	# per-class sprites later as a pure art pass" decision.
	sprite.modulate = sprite.modulate * CharacterClasses.get_color(class_id)
	# (2026-07-23) ...but a tint alone is invisible mid-fight against a busy
	# background, and it was the SAME visual idea elites used. A soft ground
	# glow in the class's vfx colour gives the player its own shape language
	# (boss = orbiting runes, elite = angular spikes, player = a pool of light).
	var aura := PlayerAura.new()
	aura.color = CharacterClasses.get_vfx_color(class_id)
	add_child(aura)


func _physics_process(delta: float) -> void:
	if is_dead or GameManager.state in [GameManager.State.LEVEL_UP, GameManager.State.WAVE_UPGRADE, GameManager.State.PAUSED, GameManager.State.GAME_OVER]:
		return

	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)

	if _is_dashing:
		# Dash owns velocity.x for its whole duration -- normal movement input
		# is ignored until it ends, so a dash always covers its full distance
		# instead of being cut short by whatever direction is still held.
		_dash_time_remaining -= delta
		if _dash_time_remaining <= 0.0:
			_end_dash()
		velocity.y = 0.0
		move_and_slide()
		global_position.x = clampf(global_position.x, MIN_X, MAX_X)
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
		_last_move_dir = move_dir
	else:
		velocity.x = 0.0

	var dash_key_down := Input.is_key_pressed(KEY_SPACE)
	if dash_key_down and not _dash_key_was_down:
		try_dash()
	_dash_key_was_down = dash_key_down

	var ult_key_down := Input.is_key_pressed(KEY_Q)
	if ult_key_down and not _ult_key_was_down:
		try_use_ultimate()
	_ult_key_was_down = ult_key_down

	velocity.y = 0.0
	move_and_slide()
	global_position.x = clampf(global_position.x, MIN_X, MAX_X)


func try_dash() -> bool:
	# Shared gated entry point for both triggers -- the Space poll in
	# _physics_process() and HUD's on-screen DashButton (the touch/mobile
	# path), same convention as try_use_ultimate(). is_dead/paused gating
	# isn't needed here: the key poll already sits behind _physics_process()'s
	# own state guard, and HUD (default process_mode) is frozen while paused.
	if is_dead or _is_dashing or _dash_cooldown_remaining > 0.0:
		return false
	_start_dash()
	return true


func _start_dash() -> void:
	_is_dashing = true
	_is_invulnerable = true
	_dash_time_remaining = DASH_DURATION
	_dash_cooldown_remaining = DASH_COOLDOWN
	velocity.x = _last_move_dir * DASH_SPEED
	_play_dash_visual()
	SignalBus.player_dashed.emit()


func _end_dash() -> void:
	_is_dashing = false
	_is_invulnerable = false


func _play_dash_visual() -> void:
	if _dash_tween:
		_dash_tween.kill()
	sprite.modulate.a = 1.0
	_dash_tween = create_tween()
	_dash_tween.tween_property(sprite, "modulate:a", DASH_ALPHA_DIP, DASH_DURATION * 0.4)
	_dash_tween.tween_property(sprite, "modulate:a", 1.0, DASH_DURATION * 0.6)


func _on_enemy_died_charge_ultimate() -> void:
	# Charge accrues even before the ultimate is unlocked -- reaching the unlock
	# tier with a full bar already waiting is the reward for the climb, not a
	# second grind stacked on top of it.
	ultimate_charge = mini(ultimate_charge + 1, ULTIMATE_KILLS_REQUIRED)


func is_ultimate_unlocked() -> bool:
	return active_element != -1 and get_element_tier(active_element) >= ULTIMATE_UNLOCK_TIER


func can_use_ultimate() -> bool:
	return is_ultimate_unlocked() and ultimate_charge >= ULTIMATE_KILLS_REQUIRED


func try_use_ultimate() -> bool:
	# Shared entry point for both triggers -- the Q key poll in
	# _physics_process() and HUD's on-screen UltimateButton (the touch/mobile
	# path, since this project ships to GitHub Pages where a keyboard isn't
	# guaranteed). Gating lives here so neither caller can bypass it.
	if not can_use_ultimate():
		return false
	_use_ultimate()
	return true


func _use_ultimate() -> void:
	ultimate_charge = 0
	var element_name := ""
	var dmg := 0.0
	var status_duration := 0.0
	match active_element:
		UpgradeResource.ElementType.FIRE:
			element_name = StatusEffects.FIRE
			dmg = ULTIMATE_FIRE_DAMAGE * fire_skill_dmg_mult
			status_duration = StatusEffects.FIRE_DURATION + fire_duration_bonus
		UpgradeResource.ElementType.FROST:
			element_name = StatusEffects.FROST
			dmg = ULTIMATE_FROST_DAMAGE * frost_skill_dmg_mult
			status_duration = ULTIMATE_FROST_FREEZE_DURATION + frost_duration_bonus
		UpgradeResource.ElementType.LIGHTNING:
			element_name = StatusEffects.LIGHTNING
			dmg = ULTIMATE_LIGHTNING_DAMAGE * lightning_skill_dmg_mult
			status_duration = StatusEffects.LIGHTNING_DURATION
	if element_name == "":
		return
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(ULTIMATE_SHAKE_INTENSITY, ULTIMATE_SHAKE_DURATION)
	# Snapshot the group first -- damage can kill (and burst/combo chains can
	# kill neighbors), and mutating group membership mid-iteration while also
	# iterating it is exactly the kind of subtle skip this avoids.
	var targets: Array = get_tree().get_nodes_in_group("enemy")
	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		match element_name:
			StatusEffects.FIRE:
				ImpactVFX.fire_explosion(enemy.global_position, 40.0, self)
			StatusEffects.FROST:
				ImpactVFX.ice_burst(enemy.global_position, 40.0, self)
			StatusEffects.LIGHTNING:
				ImpactVFX.spark_burst(enemy.global_position, 40.0, self)
		enemy.take_damage(dmg, element_name)
		if is_instance_valid(enemy) and enemy.has_method("apply_status"):
			# allow_spread=false via apply() directly -- everything on screen is
			# already being hit, a spread roll per enemy would just be N wasted
			# group scans in the same frame.
			StatusEffects.apply(enemy, element_name, status_duration, false)
	_stop_idle_bob()
	_play_recoil(1.5)
	if sprite.animation != "attack":
		sprite.play("attack")
	SignalBus.player_ultimate_used.emit()


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
	# The physical line (Piercing Arrow/Trap Shot/Trap Mastery) no
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
			cooldown_mult = maxf(cooldown_mult - 0.03, COOLDOWN_MULT_FLOOR)
		"projectile_count":
			bonus_projectile_count += 1
		"chain":
			bonus_chain_count = mini(bonus_chain_count + 1, MAX_CHAIN_COUNT)
		"projectile_speed":
			projectile_speed_mult += 0.05
		"crit_chance":
			crit_chance = minf(crit_chance + 0.02, CRIT_CHANCE_MAX)
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
	# Track picks of capped repeatable (tier-0) stat cards so the wave picker can
	# stop offering one once it reaches max_stacks (CLASS/PHYSICAL branches below
	# are tier >= 1, so they never count here).
	if upgrade.tier == 0 and upgrade.max_stacks > 0:
		repeatable_stacks[upgrade.id] = int(repeatable_stacks.get(upgrade.id, 0)) + 1
	if upgrade.element == UpgradeResource.ElementType.CLASS:
		# (2026-07-21) Class skill line: a 4th auto-firing attack source,
		# tiered 1-3, skills defined per class in CharacterClasses.CLASSES
		# ("skills" array, index = tier - 1). Loaded lazily -- only the
		# picked class's skills ever load in a run. Mirrors the elemental
		# lines' tier-swap convention exactly.
		class_skill_level += 1
		var skill_paths: Array = CharacterClasses.CLASSES.get(active_class_id, {}).get("skills", [])
		if class_skill_level <= skill_paths.size():
			_current_class_skill = load(skill_paths[class_skill_level - 1])
			_refresh_class_skill_timer()
			if class_skill_timer.is_stopped():
				class_skill_timer.start()
		_apply_upgrade_stats(upgrade)
		# Deliberately NOT emitting the player's own skill_unlocked signal --
		# HUD routes that to the basic-line label (its elemental filter only
		# knows the 3 element arrays), so a class skill would wrongly
		# overwrite the basic skill display. SignalBus covers the audio cue;
		# class_skill_changed drives the class line's own top-left HUD row.
		SignalBus.skill_unlocked.emit(_current_class_skill)
		class_skill_changed.emit(_current_class_skill)
		return
	if upgrade.element == UpgradeResource.ElementType.FUSION:
		# Stat-only, no tiers -- but the cooldown card has to re-latch the
		# running timer, same as the elemental cooldown cards do.
		_apply_upgrade_stats(upgrade)
		_refresh_fusion_timer()
		return
	if upgrade.element == UpgradeResource.ElementType.PHYSICAL:
		physical_level += 1
		match physical_level:
			1: _current_skill = piercing_arrow
			2: _current_skill = chain_arrow
			# (2026-07-24) The physical line is now just these two tiers, and
			# that is deliberate. It used to run Multishot -> Piercing Arrow ->
			# Trap Shot -> three trap upgrades, which fought itself twice over:
			# Multishot granted 3 arrows and Piercing Arrow (the very next tier)
			# declares projectile_count = 1, taking two straight back; and Trap
			# Shot ignores arrow count entirely, so every arrow-growth pick went
			# dead the moment the line reached it. Multishot was removed first,
			# then the traps became the Trapper class.
			#
			# What's left is a line about ARROWS: Piercing Arrow, then Spread
			# Arrow which also splashes each hit onto nearby enemies. All further
			# growth comes from the two capped repeatable cards -- "+1 Arrow" to
			# MAX_SHOT_COUNT and "+1 Chain" to MAX_CHAIN_COUNT -- each of which
			# stops being offered once capped, so the line finishes cleanly
			# instead of trailing dead picks.
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
		_maybe_unlock_fusions(upgrade.element)
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


# --- Elemental fusions (late-game: max two element lines) -----------------------

func _element_status_name(element: int) -> String:
	# Maps an UpgradeResource.ElementType enum to StatusEffects' status-name
	# string ("fire"/"frost"/"lightning"); "" for non-status lines.
	match element:
		UpgradeResource.ElementType.FIRE:
			return StatusEffects.FIRE
		UpgradeResource.ElementType.FROST:
			return StatusEffects.FROST
		UpgradeResource.ElementType.LIGHTNING:
			return StatusEffects.LIGHTNING
	return ""


func _maybe_unlock_fusions(element: int) -> void:
	# Called after an element line levels up. If this line just reached
	# FUSION_UNLOCK_TIER, pair it with any OTHER line already at that tier into a
	# fusion (once per pair).
	var el := _element_status_name(element)
	if el == "" or get_element_tier(element) < FUSION_UNLOCK_TIER:
		return
	for other in [UpgradeResource.ElementType.FIRE, UpgradeResource.ElementType.FROST, UpgradeResource.ElementType.LIGHTNING]:
		if other == element or get_element_tier(other) < FUSION_UNLOCK_TIER:
			continue
		var pid := ElementFusions.pair_id(el, _element_status_name(other))
		if pid in active_fusions:
			continue
		active_fusions.append(pid)
		var fname: String = ElementFusions.FUSIONS[pid]["name"]
		fusion_unlocked.emit(pid, fname)
		SignalBus.fusion_unlocked.emit(pid, fname)


func get_fusion_partners(element: String) -> Array[String]:
	# The partner status-name(s) an active fusion adds to attacks that apply
	# `element` -- e.g. with Frostfire unlocked, a fire hit also applies frost.
	# Usually 0 or 1; can be 2 if all three lines are maxed (all fusions active).
	# (2026-07-23) Only the EQUIPPED fusion fuses. Previously every unlocked
	# fusion applied its partner status automatically, which left the new
	# Activate button with nothing to do -- unlocking was the whole effect. Now
	# unlocking makes a fusion available and equipping it is what fuses your
	# attacks, so the choice between them actually matters.
	var partners: Array[String] = []
	if active_fusion_id == "":
		return partners
	var p := ElementFusions.partner(active_fusion_id, element)
	if p != "":
		partners.append(p)
	return partners


func get_current_physical_skill() -> SkillData:
	return _current_skill


func get_current_class_skill() -> SkillData:
	return _current_class_skill


func get_current_skill_for_element(element: int) -> SkillData:
	return _current_skill_for_element(element)


func select_active_element(element: int) -> void:
	# Called directly by the HUD when the player taps a specific unlocked
	# element's icon -- picks that exact element rather than cycling, so
	# there's no ambiguity about which path becomes active (a blind
	# next-in-list cycle was confusing once 3 elements were unlocked: tapping
	# it didn't reliably return to the path the player expected).
	if _current_skill_for_element(element) == null:
		return  # not actually unlocked yet -- ignore rather than activate a blank skill
	# Picking an element always un-equips a fusion, even if that element was
	# already active -- otherwise there'd be no way back off a fusion.
	var had_fusion := active_fusion_id != ""
	_deactivate_fusion()
	if element == active_element and not had_fusion:
		return
	var old_timer := get_elemental_timer_by_element(active_element)
	if is_instance_valid(old_timer):
		old_timer.stop()
	active_element = element
	_refresh_elemental_timer(element)
	get_elemental_timer_by_element(element).start()
	active_element_switched.emit(element, _current_skill_for_element(element))


# --- Fusion as an equippable attack line ---------------------------------------

func select_active_fusion(pair_id: String) -> bool:
	# Equipping a fusion REPLACES the active element: the elemental timer stops
	# and the fusion's own timer takes over, so the player fires the fused
	# projectile instead of fire/frost/lightning. Only an unlocked fusion can be
	# equipped.
	if not (pair_id in active_fusions):
		return false
	if pair_id == active_fusion_id:
		return true
	var old_timer := get_elemental_timer_by_element(active_element)
	if is_instance_valid(old_timer):
		old_timer.stop()
	active_fusion_id = pair_id
	_current_fusion_skill = load(ElementFusions.skill_path(pair_id))
	_refresh_fusion_timer()
	fusion_skill_timer.start()
	active_fusion_changed.emit(pair_id, _current_fusion_skill)
	return true


func _deactivate_fusion() -> void:
	if active_fusion_id == "":
		return
	active_fusion_id = ""
	_current_fusion_skill = null
	if is_instance_valid(fusion_skill_timer):
		fusion_skill_timer.stop()
	active_fusion_changed.emit("", null)


func _refresh_fusion_timer() -> void:
	if _current_fusion_skill != null and is_instance_valid(fusion_skill_timer):
		fusion_skill_timer.wait_time = _current_fusion_skill.cooldown * maxf(fusion_cd_mult, 0.3)


func get_current_fusion_skill() -> SkillData:
	return _current_fusion_skill


func _on_fusion_skill_timeout() -> void:
	if is_dead or _current_fusion_skill == null or active_fusion_id == "":
		return
	# Fired as one of its two parent elements; StatusEffects.apply() then adds
	# the partner automatically (see get_fusion_partners()), which is what makes
	# the pair's combo detonate on essentially every hit. That combo IS the
	# fusion's payoff, so nothing extra is needed here.
	var els: Array = ElementFusions.FUSIONS[active_fusion_id]["elements"]
	var element_name: String = els[0]
	var duration := StatusEffects.FIRE_DURATION + fire_duration_bonus
	match element_name:
		StatusEffects.FROST:
			duration = StatusEffects.FROST_DURATION + frost_duration_bonus
		StatusEffects.LIGHTNING:
			duration = StatusEffects.LIGHTNING_DURATION
	_fire_elemental_skill(_current_fusion_skill, element_name, fusion_dmg_mult, duration)


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
		# (2026-07-21) Same no-target guard as the non-rain branch below and
		# _fire_trap_shot() -- without it Burning Rain/Thunder Storm cast into
		# empty space in front of the player whenever nothing was nearby,
		# per direct user report.
		if _get_nearest_enemies(1).is_empty():
			return
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
	# The fusion line has its own projectile-speed upgrade card, which only
	# applies to the fusion's own shots -- without this the card would set a
	# stat nothing ever reads.
	var fusion_speed: float = fusion_projectile_speed_mult if skill == _current_fusion_skill else 1.0
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult * fusion_speed
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	var aim_point := _predict_intercept(attack_origin.global_position, targets[0], proj_speed)
	var base_dir := (aim_point - attack_origin.global_position).normalized()
	for i in shot_count:
		var dir := base_dir.rotated(_spread_offset(i, shot_count))
		var dmg := skill.base_damage * dmg_mult * (2.0 if randf() < crit_chance else 1.0)
		var proj: Projectile = pool.acquire(skill.projectile_scene)
		# Only the dead-center shot (i==0) homes and is guaranteed to connect --
		# the fanned side shots keep their fixed trajectory, same bonus-AOE role
		# they've always had, so a multi-arrow shot still reads as a fan rather
		# than every arrow collapsing onto one target. (2026-07-24) Those extra
		# arrows now come solely from "+1 Arrow"; the Multishot tier is gone.
		var homing_target: Node2D = targets[0] if i == 0 else null
		proj.activate(dir, proj_speed, dmg, attack_origin.global_position, skill.pierce_count, "enemy", PLAYER_SHOT_MAX_RANGE, status_rolls, skill.burst_radius, effective_chain_count(skill), skill.visual_scale, skill.burst_vfx_id, homing_target)


func _fire_elemental_rain(skill: SkillData, dmg_mult: float, status_rolls: Array[Dictionary]) -> void:
	# Burning Rain / Thunder Storm (tier 3): a telegraphed area strike, same
	# as the basic line's Arrow Rain -- see _fire_area_strike().
	var color := AREA_STRIKE_COLOR_LIGHTNING
	if not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.FIRE:
		color = AREA_STRIKE_COLOR_FIRE
	_fire_area_strike(skill, dmg_mult, status_rolls, color)


func _refresh_timer_cooldowns() -> void:
	attack_timer.wait_time = _current_skill.cooldown * cooldown_mult
	_refresh_class_skill_timer()  # class line shares the basic line's cooldown_mult, so a Reduce Cooldown pick reaches it too


func _refresh_class_skill_timer() -> void:
	if _current_class_skill != null:
		class_skill_timer.wait_time = maxf(_current_class_skill.cooldown * cooldown_mult, 0.05)


func _on_class_skill_timeout() -> void:
	_fire_class_skill(_current_class_skill)


func _fire_class_skill(skill: SkillData) -> void:
	if skill == null:
		return
	var no_status: Array[Dictionary] = []
	match skill.fire_mode:
		SkillData.FireMode.ARROW_RAIN:
			if _get_nearest_enemies(1).is_empty():
				return
			# Bright class-colored telegraph instead of the muted basic gold, so
			# the class storm reads as a distinct, punchy effect.
			var tele: Color = CharacterClasses.get_vfx_color(active_class_id)
			_fire_area_strike(skill, damage_mult, no_status, Color(tele.r, tele.g, tele.b, 0.55))
		SkillData.FireMode.SELF_BURST:
			if not _fire_self_burst(skill):
				return
		SkillData.FireMode.TRAP_SHOT:
			# (2026-07-24) Added for the Trapper class. Without this case a trap
			# skill fell through to _fire_class_projectile(), which needs a
			# projectile_scene a trap skill doesn't have -- the class would have
			# silently fired nothing at all.
			if not _fire_trap_shot(skill):
				return
		_:
			if not _fire_class_projectile(skill):
				return
	_stop_idle_bob()
	_play_recoil(_recoil_intensity_for(skill))
	if sprite.animation != "attack":
		sprite.play("attack")
	SignalBus.player_shot.emit()


func _fire_class_projectile(skill: SkillData) -> bool:
	# Class-line projectiles: pure physical (no status rolls, untyped damage,
	# so boss affinities never touch them), scaled by damage_mult + crit like
	# the basic line, center shot homing like the elemental lines.
	var targets := _get_nearest_enemies(1)
	if targets.is_empty():
		return false
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if not is_instance_valid(pool):
		return false
	var no_status: Array[Dictionary] = []
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult
	var aim_point := _predict_intercept(attack_origin.global_position, targets[0], proj_speed)
	var base_dir := (aim_point - attack_origin.global_position).normalized()
	# Bright per-hit flash + a glow tint on the arrow itself -- class projectiles
	# otherwise produce NO impact VFX at all (no burst_radius), so they read as
	# flat. The flash is visual-only (no splash damage). Bigger visual scale on
	# top of each skill's own so the class line clearly out-sizes the basic arrow.
	var flash_col: Color = CharacterClasses.get_vfx_color(active_class_id)
	var flash_radius := 46.0
	var vis_scale: float = maxf(skill.visual_scale, 1.0) * 1.35
	for i in skill.projectile_count:
		var dir := base_dir.rotated(_spread_offset(i, skill.projectile_count))
		var dmg := skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
		var proj: Projectile = pool.acquire(skill.projectile_scene)
		var homing_target: Node2D = targets[0] if i == 0 else null
		proj.activate(dir, proj_speed, dmg, attack_origin.global_position, skill.pierce_count, "enemy", PLAYER_SHOT_MAX_RANGE, no_status, skill.burst_radius, effective_chain_count(skill), vis_scale, skill.burst_vfx_id, homing_target, flash_col, flash_radius)
	return true


func _fire_self_burst(skill: SkillData) -> bool:
	# Juggernaut's Shockwave/Quake/Second Wind: an AoE pulse centered on the
	# PLAYER (trap_radius = pulse radius), not on enemies. Only fires when
	# something is actually in range -- same no-wasted-cast rule as every
	# other fire mode -- which doubles as the heal gate: Second Wind can't be
	# idled for free HP with no enemies near.
	var radius: float = skill.trap_radius
	var in_range: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if enemy.global_position.distance_to(global_position) <= radius:
			in_range.append(enemy)
	if in_range.is_empty():
		return false
	if skill.burst_vfx_id == "quake":
		ImpactVFX.ground_spikes(global_position, radius, self)
	else:
		ImpactVFX.ground_shockwave(global_position, radius, self)
	# Big bright class-colored ring on top of the ground VFX + a real camera
	# shake, so the pulse lands with weight instead of a faint scuff.
	var pulse_col: Color = CharacterClasses.get_vfx_color(active_class_id)
	ImpactVFX.flash_burst(global_position, radius * 1.15, pulse_col, self)
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(9.0, 0.22)
	var dmg := skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	for enemy in in_range:
		enemy.take_damage(dmg)
	if skill.heal_on_cast > 0.0 and current_hp < max_hp:
		current_hp = minf(current_hp + skill.heal_on_cast, max_hp)
		hp_changed.emit(current_hp, max_hp)
		SignalBus.player_healed.emit(skill.heal_on_cast)
	return true


func _on_attack_timeout() -> void:
	_auto_fire(_current_skill)


func _auto_fire(skill: SkillData) -> void:
	match skill.fire_mode:
		SkillData.FireMode.ARROW_RAIN:
			# (2026-07-21) Same no-target guard as the "_" branch below and
			# TRAP_SHOT above -- Arrow Rain used to cast into empty space in
			# front of the player whenever nothing was nearby.
			if _get_nearest_enemies(1).is_empty():
				return
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
	# Scatters impact zones around real enemies, shows a warning circle on
	# each, then guarantee-hits everything caught inside once the telegraph
	# resolves -- matches the plan docs' "warning marker -> impact" framing
	# and reuses boss_base.gd's own telegraphed-zone pattern.
	# (2026-07-21) No targets used to fall back to random zones scattered
	# above the player -- same "cast at nothing" waste as Trap Shot already
	# guards against. Callers now check emptiness before ever calling this
	# (see _auto_fire()/_fire_elemental_skill()), but this stays as a
	# defense-in-depth guard rather than trusting every future caller to
	# remember that check.
	var targets := _get_nearest_enemies(skill.rain_arrow_count + bonus_zones)
	if targets.is_empty():
		return
	var zone_count: int = skill.rain_arrow_count + bonus_zones
	var scatter: float = skill.rain_spread_width
	var radius: float = skill.trap_radius
	# Burning Rain and Thunder Storm each get their own falling/impact art
	# instead of the plain procedural circle basic Arrow Rain still uses.
	var is_fire = not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.FIRE
	var is_lightning = not status_rolls.is_empty() and status_rolls[0]["element"] == StatusEffects.LIGHTNING
	var points: Array[Vector2] = []
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
		var strike_element: String = status_rolls[0]["element"] if not status_rolls.is_empty() else ""
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
				continue
			if enemy.global_position.distance_to(p) > radius:
				continue
			enemy.take_damage(dmg, strike_element)
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
	trap.activate(dmg, skill.trap_duration, skill.trap_radius, target.global_position, no_status_rolls, trap_detonate_mult)
	get_tree().current_scene.add_child(trap)
	return true


func _spread_offset(i: int, shot_count: int) -> float:
	# Shot 0 is always the guaranteed dead-center hit on the real target;
	# the rest fan outward in alternating +/- SPREAD_STEP_DEGREES steps:
	# [0, +8, -8, +16, -16, ...]. A purely symmetric spread (an earlier
	# approach) has no exact center shot whenever shot_count is even -- e.g.
	# 4 shots would land at +/-7.5/+/-22.5 degrees (back when the step was
	# 15), so every single arrow misses a stationary target dead ahead.
	# Since bonus_projectile_count ("+1 Arrow") drives the count up from a base
	# of 1, both odd and even totals occur; this isn't an edge case, it needs to
	# hold for every shot_count.
	if i == 0:
		return 0.0
	var step := (i + 1) / 2
	var sign := 1.0 if i % 2 == 1 else -1.0
	return deg_to_rad(SPREAD_STEP_DEGREES * step * sign)


# (2026-07-24) How many nearby enemies a hit spreads to: the skill's own
# chain_count plus every "+1 Chain" pick, clamped to MAX_CHAIN_COUNT. Public
# so the level-up popup can tell whether another pick would still do anything,
# rather than re-deriving the same clamp and drifting from it.
func effective_chain_count(skill: SkillData) -> int:
	if skill == null:
		return 0
	return mini(skill.chain_count + bonus_chain_count, MAX_CHAIN_COUNT)


func _fire_at(target: Node2D, skill: SkillData, angle_offset: float = 0.0) -> void:
	var proj_speed: float = BASE_PROJECTILE_SPEED * projectile_speed_mult
	var aim_point := _predict_intercept(attack_origin.global_position, target, proj_speed)
	var dir := (aim_point - attack_origin.global_position).normalized().rotated(angle_offset)
	var dmg := skill.base_damage * damage_mult * (2.0 if randf() < crit_chance else 1.0)
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	var proj = pool.acquire(skill.projectile_scene)
	# (2026-07-24) This path previously used activate()'s defaults from
	# max_range onward, which meant chain_count was always 0 here -- the basic
	# line simply could not spread. That was fine while nothing on the physical
	# line chained; Chain Arrow and the "+1 Chain" card both live here now, so
	# the count has to be passed or every spread pick would do nothing.
	#
	# The typed local is required, not stylistic: a bare `[]` literal does not
	# coerce across activate()'s `Array[Dictionary]` parameter, and the call
	# fails outright -- the shot silently stops firing. Same trap already
	# documented in _fire_trap_shot(), and it bit again here.
	var no_status_rolls: Array[Dictionary] = []
	proj.activate(dir, proj_speed, dmg, attack_origin.global_position, skill.pierce_count, "enemy",
		PLAYER_SHOT_MAX_RANGE, no_status_rolls, skill.burst_radius, effective_chain_count(skill))


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


# (2026-07-24) Every ordinary hit costs exactly HIT_COST, whatever hit you and
# whatever wave it is -- per user: "A hit need to reduce character 1 hp, no
# reduct function needed". Enforced here rather than at each damage site because
# every regular source (contact, enemy arrows, an enemy leaking off the bottom)
# already funnels through this one method, so no future attack can reintroduce
# its own scale. Incoming `amount` is therefore deliberately ignored.
#
# `_element` is accepted-but-ignored purely for signature compatibility:
# Projectile calls `take_damage(damage, element)` on whatever it hits, without
# knowing whether that's an enemy or the player. Before this parameter existed
# the player's 1-arg method could NOT satisfy that 2-arg call, so every enemy
# and boss arrow that reached the player failed at runtime and dealt nothing --
# a second, independent cause of the "HP doesn't go down when I'm hit" report,
# on top of the Cursed Wraith's missing contact damage.
const HIT_COST := 1.0


func take_damage(_amount: float, _element: String = "") -> void:
	_receive_damage(HIT_COST)


# (2026-07-24) Bosses are the deliberate exception to the flat rule, per user:
# "keep boss damage weighted, exempt bosses from flat 1 hp". A Leap Smash is
# supposed to hurt more than a bat nibble, and every boss attack already carries
# its own tuned number x _damage_mult. Named distinctly rather than adding a
# bool flag so a call site cannot pass the wrong one by accident.
func take_boss_damage(amount: float) -> void:
	_receive_damage(amount)


func _receive_damage(amount: float) -> void:
	if _is_invulnerable or _revive_invuln:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	hp_changed.emit(current_hp, max_hp)
	SignalBus.player_damaged.emit(amount)
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(6.0, 0.18)
	if current_hp <= 0.0 and not is_dead:
		_go_down()


# (2026-07-16) A loss condition that isn't damage-based -- an advancing boss
# (Corrupted Forest Guardian) reaching its lose line calls this directly
# instead of dealing lethal damage, so GameOverScreen (which only listens for
# the `died` signal) doesn't need its own separate "boss reached the bottom"
# path. Routes through the same continue flow (revive pushes the boss back
# up off the lose line, see _revive_clear_field()).
func force_defeat() -> void:
	if is_dead:
		return
	current_hp = 0.0
	hp_changed.emit(current_hp, max_hp)
	_go_down()


func _go_down() -> void:
	# HP hit 0. Offer a continue if one's left; otherwise it's the real end.
	is_dead = true
	if continues_used < MAX_CONTINUES:
		SignalBus.player_downed.emit(continues_used)
	else:
		_die_final()


func _die_final() -> void:
	if _run_over:
		return
	_run_over = true
	died.emit()
	SignalBus.player_died.emit()


func revive() -> void:
	# Called by ContinuePopup when the player accepts a continue (the popup has
	# already charged essence for the paid one). Full HP, a window of
	# invulnerability, and a cleared field so you don't die again on frame 1.
	continues_used += 1
	is_dead = false
	current_hp = max_hp
	hp_changed.emit(current_hp, max_hp)
	_revive_clear_field()
	_grant_revive_invuln()
	SignalBus.player_healed.emit(max_hp)


func decline_continue() -> void:
	# Player chose to give up (or couldn't afford the paid continue).
	_die_final()


func _revive_clear_field() -> void:
	# Regular enemies get sent back to the top so they must fall again; a boss
	# that had advanced onto the lose line is nudged back to its engage line so
	# the revive doesn't instantly re-trigger force_defeat(). No kills (avoids
	# XP/essence-reward spam) -- just breathing room.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy is BossBase:
			if enemy.global_position.y > enemy.engage_y:
				enemy.global_position.y = enemy.engage_y
		else:
			enemy.global_position.y = -40.0


func _grant_revive_invuln() -> void:
	_revive_invuln = true
	var blink := create_tween()
	blink.set_loops(int(REVIVE_INVULN_TIME / 0.2))
	blink.tween_property(sprite, "modulate:a", 0.3, 0.1)
	blink.tween_property(sprite, "modulate:a", 1.0, 0.1)
	get_tree().create_timer(REVIVE_INVULN_TIME, false).timeout.connect(func():
		if is_instance_valid(self):
			_revive_invuln = false
			sprite.modulate.a = 1.0
	)


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
