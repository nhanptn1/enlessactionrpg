extends CharacterBody2D
class_name BossBase

# Not an EnemyBase: a phase/telegraph attack pattern is a different shape than
# EnemyBase's "walk down, contact-damage on overlap" loop. This keeps its own
# take_damage()/_die() (emitting the same `died` signal EnemyBase does, so
# WaveManager handles both uniformly) but owns movement/attack logic outright.

const HIT_FLASH_DURATION := 0.08
const HIT_PUNCH_SCALE := 1.06
const DEATH_FADE_DURATION := 0.4
# (2026-07-16) Once engaged, the sprite used to freeze completely (sprite.stop()
# + frame 0) for the rest of the fight -- fixed the earlier "walking in place"
# bug, but replaced it with an equally bad "the boss is a dead still image and
# never reacts to its own attacks" problem (user: "run a bit and stop there...
# attack seem stuck sometime... still a prototype, not real effect"). No boss
# has dedicated attack art, so this fakes real feedback from the existing
# idle/move frames via position/scale tweens instead: a subtle idle bob while
# waiting (mirrors player.gd's own _start_idle_bob()), and a windup lunge
# toward the target during every attack's telegraph window.
const IDLE_BOB_AMPLITUDE := 3.0
const IDLE_BOB_DURATION := 1.3
const ATTACK_LUNGE_DISTANCE := 14.0
const ATTACK_LUNGE_SCALE_PUNCH := 1.12
const IMPACT_FLASH_RADIUS := 40.0

# (2026-07-16) "advancing" bosses -- now both Corrupted Forest Guardian and
# Dark Ranger Commander (see each scene's advances_to_lose_line override) --
# no longer stop permanently once engaged -- they keep slowly walking toward
# LOSE_LINE_Y between attacks (paused only for each attack's own
# telegraph+strike window), and reaching it is a real loss condition, not
# just a damage race. (2026-07-16) 10.0->6.0 per direct user request to slow
# every boss's advance further -- but a throwaway headless test (real boss,
# real timers, sampled position over 15s) measured this as only ~4.2px/s
# *effective* (attack telegraphs pause movement ~28% of the time for the
# golem's attack pool), i.e. ~131s to cross the full 550px from engage_y to
# LOSE_LINE_Y -- imperceptibly slow next to the boss's own +/-3px idle bob.
# (2026-07-16) 6.0->26.0 per direct user request to bring that down to ~30s:
# 550px / 30s = ~18.3px/s effective needed; at ~72% move-uptime that's
# 18.3/0.72 ~= 25.4px/s raw, rounded up slightly. Re-measured after the
# change with the same throwaway-test methodology -- see PROJECT_SUMMARY.md.
const POST_ENGAGE_WALK_SPEED := 20.0  # (2026-07-20) 26.0->20.0 per direct user request to slow boss waves further
const LOSE_LINE_Y := 950.0  # player sits at y=1150 (Main.tscn) -- this leaves a real buffer, not literal contact
const PRE_ENGAGE_SPEED_MULT := 0.5  # (2026-07-20) 0.6->0.5, same request -- applied to EnemyData.base_speed for the initial walk-in, see _ready()

# Golem's ranged attack -- a thrown rock, procedural (no rock art exists),
# arcs from the boss to the target over two chained tween segments (rise then
# fall) rather than a straight line, so it reads as thrown rather than teleporting.
const THROW_ROCK_DAMAGE := 1.0  # effective 2 after BOSS_DAMAGE_MULT, matching root_slam/vine_whip
const THROW_ROCK_TELEGRAPH_TIME := 0.7
const THROW_ROCK_FLIGHT_TIME := 0.55  # (2026-07-20) 0.45->0.55 per user request to slow the thrown rock further
const THROW_ROCK_ARC_HEIGHT := 40.0
const THROW_ROCK_IMPACT_RADIUS := 34.0
const THROW_ROCK_COOLDOWN := 2.2
const THROW_ROCK_COLOR := Color(0.45, 0.38, 0.32, 1.0)  # the rock's own material color -- kept dull/stone-like
# (2026-07-20) The telegraph circle used to reuse THROW_ROCK_COLOR at 0.5 alpha,
# which blends into the forest ground and reads as "no warning" per direct user
# report ("golem rock hard to see... not have warning attack before throwing").
# Every other boss telegraph in this file uses a bright, saturated warning color
# (ARROW_RAIN_COLOR, LEAP_SMASH_COLOR, SUMMON_FLAMES_COLOR below) -- give this
# one the same treatment instead of the rock's own muted tone.
const THROW_ROCK_TELEGRAPH_COLOR := Color(0.95, 0.8, 0.15, 0.55)

# Each boss picks a named entry via @export var attack_pattern_id below --
# one shared script serves every boss (telegraph/phase/death framework is
# 100% generic), only the attack kit itself differs per boss. Attacks not
# listed in "generic" (i.e. not backed by the shape-based telegraph system
# in _execute_attack/_apply_attack_damage/_show_telegraph) are special-cased
# by id in _execute_attack() instead -- same pattern the original
# "summon_saplings" always used, just no longer the only one.
const ATTACK_PATTERNS := {
	"forest_guardian": {
		"phase_1": ["root_slam", "vine_whip", "throw_rock"],
		"phase_2": ["poison_burst", "summon_saplings", "throw_rock"],
		"attacks": {
			# (2026-07-16) Damage values rescaled ~10x down alongside
			# player.max_hp's 100->10 rebalance, rounded to whole numbers and
			# multiplied by BOSS_DAMAGE_MULT (2.0) at the point of use --
			# effective hits: root_slam=2, vine_whip=2, poison_burst=4.
			"root_slam": {
				"damage": 1.0, "telegraph_time": 0.9, "cooldown": 2.0,
				"shape": "player_circle", "radius": 36.0, "color": Color(0.55, 0.35, 0.15, 0.5),
			},
			"vine_whip": {
				"damage": 1.0, "telegraph_time": 0.9, "cooldown": 2.2,
				"shape": "reach_line", "width": 20.0, "color": Color(0.25, 0.55, 0.2, 0.5),
			},
			"poison_burst": {
				"damage": 2.0, "telegraph_time": 1.1, "cooldown": 2.4,
				"shape": "self_circle", "radius": 100.0, "color": Color(0.5, 0.15, 0.55, 0.5),
			},
		},
	},
	"dark_ranger_commander": {
		"phase_1": ["aimed_shot", "rapid_volley"],
		"phase_2": ["arrow_rain", "shadow_step"],
		"attacks": {
			"aimed_shot": {
				"damage": 2.0, "telegraph_time": 0.8, "cooldown": 1.8,
				"shape": "reach_line", "width": 12.0, "color": Color(0.6, 0.1, 0.1, 0.55),
			},
		},
	},
	# (2026-07-16) 3rd boss -- "Fallen Knight" from docs/boss_design_attack_
	# pattern_plan.txt's Boss Concept C, built now that the golem/ranger both
	# exist. Aggressive melee identity (vs. the golem's slow tank and the
	# ranger's ranged/teleport kit): Sword Slash reuses the generic reach_line
	# system, Charge is a genuinely new special-cased dash (see _charge()) --
	# the one real new mechanic this boss adds.
	"fallen_knight": {
		"phase_1": ["sword_slash", "charge"],
		"phase_2": ["shockwave", "shield_burst"],
		"attacks": {
			"sword_slash": {
				"damage": 1.0, "telegraph_time": 0.7, "cooldown": 1.6,
				"shape": "reach_line", "width": 22.0, "color": Color(0.6, 0.63, 0.68, 0.55),
			},
			"shockwave": {
				"damage": 1.0, "telegraph_time": 1.0, "cooldown": 2.4,
				"shape": "self_circle", "radius": 90.0, "color": Color(0.5, 0.45, 0.35, 0.5),
			},
			"shield_burst": {
				"damage": 1.0, "telegraph_time": 0.9, "cooldown": 2.2,
				"shape": "self_circle", "radius": 70.0, "color": Color(0.65, 0.75, 0.9, 0.5),
			},
		},
	},
	# (2026-07-16) 4th boss -- "Demon Beast" from docs/enemy_boss_item_design.txt
	# and boss_design_attack_pattern_plan.txt's Boss Concept D, the last of the
	# 4 originally-planned bosses still unbuilt. Claw Swipe and Fire Breath both
	# reuse the generic reach_line system (Fire Breath just wider, reading as a
	# breath cone without needing real cone-shape math); Leap Smash and Summon
	# Flames are both special-cased -- Leap Smash mirrors Fallen Knight's Charge
	# (the boss repositions) but lands as an AoE circle instead of a corridor;
	# Summon Flames mirrors Dark Ranger's Arrow Rain exactly, just fire-themed.
	"demon_beast": {
		"phase_1": ["claw_swipe", "fire_breath"],
		"phase_2": ["leap_smash", "summon_flames"],
		"attacks": {
			"claw_swipe": {
				"damage": 1.0, "telegraph_time": 0.6, "cooldown": 1.5,
				"shape": "reach_line", "width": 20.0, "color": Color(0.65, 0.15, 0.05, 0.55),
			},
			"fire_breath": {
				"damage": 1.0, "telegraph_time": 0.9, "cooldown": 2.0,
				"shape": "reach_line", "width": 50.0, "color": Color(0.85, 0.35, 0.1, 0.5),
			},
		},
	},
}
const PHASE2_HP_RATIO := 0.5
const SUMMON_COOLDOWN := 5.0
const SAPLING_COUNT := 3
const INITIAL_ATTACK_DELAY := 1.5

# (2026-07-17) Phase 3 pillar 1: endless boss variety. Reuses the existing
# 4-boss rotation (WaveManager.boss_pool) rather than building new bosses --
# a random mutation is rolled onto a boss spawn from the 2nd cycle onward
# (see WaveManager.BOSS_MUTATION_*), applied generically here regardless of
# which attack_pattern_id the boss uses, so every boss in the rotation gets
# all 3 mutations for free instead of needing bespoke per-boss content.
# "color" multiplies onto sprite.modulate (same technique _play_hit_reaction()
# already uses for its white flash) -- a visible tint distinct from each
# boss's own base color, not a wholesale re-tint.
const MUTATIONS := {
	"enraged": {
		"display_name": "Enraged",
		"color": Color(1.4, 0.55, 0.4, 1.0),
		"speed_mult": 1.3,
		"damage_mult": 1.3,
		"cooldown_mult": 0.75,  # attacks recover 25% faster
	},
	"shielded": {
		"display_name": "Shielded",
		"color": Color(0.55, 0.85, 1.3, 1.0),
		"shield_interval": 6.0,  # seconds between shield windows
		"shield_duration": 1.5,  # seconds fully invulnerable per window
	},
	"volatile": {
		"display_name": "Volatile",
		"color": Color(1.3, 0.75, 0.3, 1.0),
		"zone_count": 2,
		"zone_radius": 55.0,
		"zone_damage": 1.0,  # multiplied by _damage_mult at resolve time, matching every other boss hit
		"telegraph_time": 1.0,
	},
}

# Dark Ranger Commander's special-cased (non-generic-shape) attacks.
const RAPID_VOLLEY_PROJECTILE := preload("res://scenes/effects/CursedBolt.tscn")
const RAPID_VOLLEY_DAMAGE := 1.0  # (2026-07-16) 7.0->1.0, rescaled with player.max_hp's 100->10 rebalance (effective 2 per bolt after BOSS_DAMAGE_MULT)
const RAPID_VOLLEY_SHOT_COUNT := 3
const RAPID_VOLLEY_SPREAD_DEG := 18.0
const RAPID_VOLLEY_SPEED := 210.0  # (2026-07-20) 260.0->210.0 per direct user request to slow boss projectiles a bit
const RAPID_VOLLEY_TELEGRAPH_TIME := 0.5
const RAPID_VOLLEY_COOLDOWN := 2.0
const RAPID_VOLLEY_MAX_RANGE := 1400.0  # (2026-07-16) same fix as RangedAttack.ENEMY_SHOT_MAX_RANGE -- without it these shots expired mid-flight past Projectile.DEFAULT_MAX_RANGE (900) before reaching the player
const ARROW_RAIN_DAMAGE := 1.0  # (2026-07-16) 10.0->1.0, rescaled with player.max_hp's 100->10 rebalance (effective 2 per zone after BOSS_DAMAGE_MULT)
const ARROW_RAIN_IMPACT_COUNT := 3
const ARROW_RAIN_IMPACT_RADIUS := 42.0
const ARROW_RAIN_TELEGRAPH_TIME := 1.0
const ARROW_RAIN_COOLDOWN := 2.6
const ARROW_RAIN_COLOR := Color(0.7, 0.15, 0.15, 0.5)
const SHADOW_STEP_FADE_TIME := 0.25
const SHADOW_STEP_COOLDOWN := 1.2
const SHADOW_STEP_RANGE := 160.0
const SHADOW_STEP_MIN_X := 80.0
const SHADOW_STEP_MAX_X := 640.0

# Fallen Knight's special-cased Charge -- deliberately horizontal-only (never
# touches global_position.y) so it can never interact with the post-engage
# advance-to-lose-line creep; a knight "rushing forward" reads fine as a
# quick horizontal reposition without needing to literally arrive at the
# player's exact position (which sits at a very different y).
const CHARGE_TELEGRAPH_TIME := 0.6
const CHARGE_DASH_TIME := 0.25
const CHARGE_DISTANCE := 140.0
const CHARGE_HIT_WIDTH := 44.0  # corridor width for both the telegraph and the hit-check -- see _charge()
const CHARGE_DAMAGE := 1.0  # effective 2 after BOSS_DAMAGE_MULT, matching this boss's other attacks
const CHARGE_COOLDOWN := 2.2
const CHARGE_COLOR := Color(0.65, 0.7, 0.78, 0.5)

# Demon Beast's special-cased Leap Smash -- same horizontal-only, bounded
# reposition as Charge above, but lands as an AoE circle instead of a
# corridor (telegraph and hit-check are the same circle at the same point,
# so there's no telegraph/hitbox mismatch to worry about here).
const LEAP_SMASH_TELEGRAPH_TIME := 0.7
const LEAP_SMASH_JUMP_TIME := 0.3
const LEAP_SMASH_DISTANCE := 130.0
const LEAP_SMASH_RADIUS := 60.0
const LEAP_SMASH_DAMAGE := 1.0
const LEAP_SMASH_COOLDOWN := 2.4
const LEAP_SMASH_COLOR := Color(0.7, 0.3, 0.1, 0.5)

# Demon Beast's special-cased Summon Flames -- mirrors _arrow_rain() exactly
# (scattered telegraphed zones, one resolve moment), fire-themed.
const SUMMON_FLAMES_ZONE_COUNT := 3
const SUMMON_FLAMES_ZONE_RADIUS := 40.0
const SUMMON_FLAMES_TELEGRAPH_TIME := 1.1
const SUMMON_FLAMES_COOLDOWN := 2.8
const SUMMON_FLAMES_DAMAGE := 1.0
const SUMMON_FLAMES_COLOR := Color(0.85, 0.3, 0.05, 0.5)

@export var engage_y: float = 400.0
@export var sapling_data: EnemyData
@export var attack_pattern_id: String = "forest_guardian"
@export var advances_to_lose_line: bool = false  # see LOSE_LINE_Y above -- only Corrupted Forest Guardian sets this true

@onready var sprite: AnimatedSprite2D = $Sprite

signal died(xp_reward: int, drop_chance: float, death_position: Vector2)

var data: EnemyData
var current_hp: float
var _max_hp: float
var current_phase := 1
var _engaged := false
var _walk_paused := false  # true while an attack's telegraph+strike is in progress (advancing bosses only)
var _hp_mult := 1.0
var _speed_mult := 1.0
var _damage_mult := 1.0
var _xp_override := -1
var _attack_loop_running := false
var _base_modulate: Color
var _base_scale: Vector2
var _sprite_base_position: Vector2
var _hit_tween: Tween
var _idle_tween: Tween
var _lunge_tween: Tween
var _is_dying := false
var _pattern: Dictionary
var _phase_1_attacks: Array
var _phase_2_attacks: Array
var status: Dictionary = {}  # element name (StatusEffects.FIRE/LIGHTNING/FROST) -> seconds remaining -- bosses only take DOT/combo damage, no movement lock

# "" = no mutation, the pre-Phase-3 default. Set directly by EnemySpawner
# before add_child() (mirroring how _pooled is set on regular enemies),
# not threaded through setup() -- see MUTATIONS above.
var mutation_id: String = ""
var _cooldown_mult := 1.0  # only "enraged" changes this; see _apply_mutation()
var _mutation_invulnerable := false  # "shielded" only -- see _run_shield_loop()

# (2026-07-21) Phase 4: boss variety round 2 -- elemental affinities, the
# first of the two follow-ups floated when mutations shipped. A boss with an
# affinity takes only AFFINITY_RESIST_MULT damage from its own element and
# AFFINITY_WEAK_MULT from its counter (fire<-frost, frost<-lightning,
# lightning<-fire, a closed rotation) -- physical damage is never affected,
# so a basic-line build fights every boss the same as before. The point is
# to make the player's existing element-switching mechanic matter in boss
# fights: HUD announces the affinity name, and swapping to the counter
# element is the intended answer. Rolled independently of mutation_id (the
# two can stack) by WaveManager, set by EnemySpawner the same way
# mutation_id is. "" = no affinity, the default.
const AFFINITIES := {
	"fire": {"display_name": "Flamebound", "color": Color(1.35, 0.75, 0.6, 1.0), "weak_to": "frost"},
	"frost": {"display_name": "Frostbound", "color": Color(0.65, 0.9, 1.35, 1.0), "weak_to": "lightning"},
	"lightning": {"display_name": "Stormbound", "color": Color(1.2, 1.1, 0.55, 1.0), "weak_to": "fire"},
}
const AFFINITY_RESIST_MULT := 0.5
const AFFINITY_WEAK_MULT := 1.5
var affinity_id: String = ""


func setup(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1) -> void:
	data = enemy_data  # caller MUST call this before add_child()
	_hp_mult = hp_mult
	_speed_mult = speed_mult
	_damage_mult = damage_mult
	_xp_override = xp_override


func _ready() -> void:
	add_to_group("enemy")
	_pattern = ATTACK_PATTERNS.get(attack_pattern_id, ATTACK_PATTERNS["forest_guardian"])
	_phase_1_attacks = _pattern.get("phase_1", [])
	_phase_2_attacks = _pattern.get("phase_2", [])
	_max_hp = data.base_hp * _hp_mult
	current_hp = _max_hp
	_apply_mutation()  # before velocity below (reads _speed_mult) and before _base_modulate captures sprite.modulate (must capture the tinted color, not the pre-mutation one)
	_apply_affinity()  # same ordering constraint as _apply_mutation() -- its tint must be captured into _base_modulate too
	# (2026-07-16) Bosses used to walk in at the same speed as a basic Slime
	# Scout (EnemyData.base_speed=90) -- slowed per user feedback that every
	# boss should move slower in general, not just during the post-engage
	# creep toward the lose line.
	velocity = Vector2(0, data.base_speed * PRE_ENGAGE_SPEED_MULT * _speed_mult)
	_base_modulate = sprite.modulate
	_base_scale = sprite.scale
	_sprite_base_position = sprite.position
	sprite.play("move")
	_attack_loop_running = true
	SignalBus.boss_hp_changed.emit(current_hp, _max_hp)
	# One combined announcement string covers both systems -- e.g. "Enraged",
	# "Flamebound (weak to Frost)", or "Enraged Flamebound (weak to Frost)".
	# The weak-to hint ships in the label itself: a player who doesn't know
	# the affinity rotation can't use the counter-play at all, so the label
	# must teach it, not just name it.
	var special_names: Array[String] = []
	var mutation_name: String = MUTATIONS.get(mutation_id, {}).get("display_name", "")
	if mutation_name != "":
		special_names.append(mutation_name)
	if AFFINITIES.has(affinity_id):
		var weak_to: String = AFFINITIES[affinity_id]["weak_to"]
		special_names.append("%s (weak to %s)" % [AFFINITIES[affinity_id]["display_name"], weak_to.capitalize()])
	SignalBus.boss_mutation_announced.emit(" ".join(special_names))
	SignalBus.boss_affinity_announced.emit(affinity_id)
	_run_attack_loop()
	if mutation_id == "shielded":
		_run_shield_loop()


# Applied once at spawn -- speed/damage/cooldown multiply onto the existing
# wave-cycle multipliers rather than replacing them, so a mutation composes
# with normal boss-cycle scaling instead of overriding it.
func _apply_mutation() -> void:
	if mutation_id == "" or not MUTATIONS.has(mutation_id):
		return
	var m: Dictionary = MUTATIONS[mutation_id]
	_speed_mult *= m.get("speed_mult", 1.0)
	_damage_mult *= m.get("damage_mult", 1.0)
	_cooldown_mult = m.get("cooldown_mult", 1.0)
	sprite.modulate = sprite.modulate * m["color"]


func _apply_affinity() -> void:
	# Purely a tint at spawn time -- the resist/weak math lives in
	# take_damage(), read fresh per hit, since it depends on each incoming
	# hit's element rather than any spawn-time stat.
	if affinity_id == "" or not AFFINITIES.has(affinity_id):
		return
	sprite.modulate = sprite.modulate * AFFINITIES[affinity_id]["color"]


# "Shielded" -- periodic invulnerability window, independent of the attack
# loop (runs alongside it, not inside it) so it works identically regardless
# of which attack pattern the boss uses.
func _run_shield_loop() -> void:
	var m: Dictionary = MUTATIONS["shielded"]
	var interval: float = m["shield_interval"]
	var duration: float = m["shield_duration"]
	while is_instance_valid(self) and not _is_dying:
		await get_tree().create_timer(interval, false).timeout
		if not is_instance_valid(self) or _is_dying:
			return
		_mutation_invulnerable = true
		ImpactVFX.shield_flash(global_position, 50.0, self)
		await get_tree().create_timer(duration, false).timeout
		if not is_instance_valid(self) or _is_dying:
			return
		_mutation_invulnerable = false


func _physics_process(delta: float) -> void:
	StatusEffects.tick(self, delta)
	if not is_instance_valid(self):
		return  # a Fire DOT tick can kill the boss mid-frame
	if not _engaged:
		# Recomputed from base every frame (not multiplied in place) so the
		# status slow can't compound toward zero -- see boss_speed_multiplier().
		velocity = Vector2(0, data.base_speed * PRE_ENGAGE_SPEED_MULT * _speed_mult * StatusEffects.boss_speed_multiplier(self))
		move_and_slide()
		if global_position.y >= engage_y:
			global_position.y = engage_y
			velocity = Vector2.ZERO
			_engaged = true
			# The "move" animation loops forever (matches EnemyBase's convention),
			# which looked like the boss was perpetually trying to walk in place
			# once stopped -- stand on its first frame once engaged instead of
			# looping "move" in place. But a hard freeze (no idle bob, no attack
			# reaction) read as the boss being dead/stuck for the whole fight, so
			# a subtle idle bob takes over from here instead of a total freeze.
			sprite.stop()
			sprite.frame = 0
			_start_idle_bob()
		return
	if not advances_to_lose_line or _walk_paused or _is_dying:
		return
	# Between attacks (see _pause_walk_for_attack()/_resume_walk_for_cooldown()),
	# an advancing boss keeps creeping toward the lose line instead of staying
	# put forever -- reaching it is a real loss condition, checked every frame
	# rather than only at attack boundaries so it can't be skipped by a long
	# cooldown carrying it past LOSE_LINE_Y unnoticed.
	# (2026-07-17) *_speed_mult multiplier added -- caught by review: Enraged's
	# speed boost previously only ever applied to the brief pre-engage walk-in
	# (see _ready()'s velocity line), making it invisible for the entire actual
	# fight since this post-engage creep used to read the flat constant alone.
	velocity = Vector2(0, POST_ENGAGE_WALK_SPEED * _speed_mult * StatusEffects.boss_speed_multiplier(self))
	move_and_slide()
	if global_position.y >= LOSE_LINE_Y:
		global_position.y = LOSE_LINE_Y
		_trigger_lose()


func apply_status(element: String, duration: float) -> void:
	StatusEffects.apply(self, element, duration)


func take_damage(amount: float, element: String = "") -> void:
	# `element` "" = physical/untyped -- affinity never touches it. Passed by
	# the elemental damage paths (projectile hits/bursts/chains, area strikes,
	# DOT ticks); everything else keeps calling with one arg unchanged.
	if _is_dying:
		return
	if _mutation_invulnerable:
		ImpactVFX.shield_flash(global_position, 40.0, self)  # feedback that the hit was blocked, not silently ignored
		return
	if affinity_id != "" and element != "" and AFFINITIES.has(affinity_id):
		if element == affinity_id:
			amount *= AFFINITY_RESIST_MULT
		elif element == AFFINITIES[affinity_id]["weak_to"]:
			amount *= AFFINITY_WEAK_MULT
	current_hp -= amount * StatusEffects.damage_amp(self)  # Brittle Frost: frozen bosses take extra damage too
	SignalBus.enemy_hit.emit()
	SignalBus.boss_hp_changed.emit(maxf(current_hp, 0.0), _max_hp)
	if current_hp <= 0.0:
		_die()
		return
	_play_hit_reaction()
	if current_phase == 1 and current_hp <= _max_hp * PHASE2_HP_RATIO:
		current_phase = 2
		SignalBus.boss_phase_changed.emit(current_phase)
		var cam := get_viewport().get_camera_2d()
		if is_instance_valid(cam) and cam.has_method("shake"):
			cam.shake(14.0, 0.3)


func _play_hit_reaction() -> void:
	if _hit_tween:
		_hit_tween.kill()
	sprite.scale = _base_scale
	sprite.modulate = Color(2.5, 2.5, 2.5, 1.0)
	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_property(sprite, "modulate", _base_modulate, HIT_FLASH_DURATION)
	_hit_tween.tween_property(sprite, "scale", _base_scale * HIT_PUNCH_SCALE, HIT_FLASH_DURATION * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.chain().tween_property(sprite, "scale", _base_scale, HIT_FLASH_DURATION * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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


# Every boss has only idle/move art, never a dedicated attack pose -- this
# fakes a windup by leaning the sprite toward the target and punching its
# scale up for the telegraph window, then settling back right as the hit
# resolves, so an attack reads as the boss doing something instead of a
# static image with an unrelated colored shape appearing near the player.
func _play_attack_lunge(target_pos: Vector2, duration: float) -> void:
	_stop_idle_bob()
	if _lunge_tween:
		_lunge_tween.kill()
	sprite.position = _sprite_base_position
	sprite.scale = _base_scale
	var lean: Vector2 = (target_pos - global_position).normalized() * ATTACK_LUNGE_DISTANCE
	_lunge_tween = create_tween()
	_lunge_tween.set_parallel(true)
	_lunge_tween.tween_property(sprite, "position", _sprite_base_position + lean, duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(sprite, "scale", _base_scale * ATTACK_LUNGE_SCALE_PUNCH, duration * 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.chain().set_parallel(true)
	_lunge_tween.tween_property(sprite, "position", _sprite_base_position, duration * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_lunge_tween.tween_property(sprite, "scale", _base_scale, duration * 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# No auto-restart of idle bob here (unlike the first version of this fix) --
	# an advancing boss needs to switch to its walk animation instead once the
	# attack resolves, not idle bob, so the caller decides via
	# _resume_walk_for_cooldown() right after applying damage.


# Attacks pause the boss's own advance toward the lose line for their
# telegraph+strike window (walking and winding up to strike at the same time
# would look wrong), freezing on a standing frame -- _play_attack_lunge()
# then takes over the sprite's position/scale for that same window.
func _pause_walk_for_attack() -> void:
	_walk_paused = true
	velocity = Vector2.ZERO
	if _idle_tween:
		_idle_tween.kill()
	sprite.stop()
	sprite.frame = 0


# Called right after an attack's damage resolves -- an advancing boss resumes
# its walk animation and starts creeping toward the lose line again for the
# cooldown gap until the next attack; a non-advancing boss (or one that's
# mid-death) just goes back to idle-bobbing in place, matching the original
# post-engage behavior exactly.
func _resume_walk_for_cooldown() -> void:
	_walk_paused = false
	if not is_instance_valid(self) or _is_dying:
		return
	if advances_to_lose_line:
		sprite.play("move")
	else:
		_start_idle_bob()


func _trigger_lose() -> void:
	_attack_loop_running = false
	set_physics_process(false)
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("force_defeat"):
		player.force_defeat()


func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	_attack_loop_running = false
	if mutation_id == "volatile":
		_spawn_volatile_death_zones()  # captures everything it needs into local closures before self is freed below
	StatusEffects.explode_on_death(self)  # Explosive Volley: no-op unless burning and the player has the branch
	var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
	died.emit(xp_reward, data.drop_chance, global_position)
	SignalBus.enemy_died.emit()
	set_physics_process(false)
	if _idle_tween:
		_idle_tween.kill()
	if _lunge_tween:
		_lunge_tween.kill()
	sprite.position = _sprite_base_position
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(sprite, "scale", Vector2.ZERO, DEATH_FADE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_DURATION)
	death_tween.chain().tween_callback(queue_free)


# "Volatile" -- telegraphed damage zones around the death position, resolving
# after this boss instance is already gone (its own death_tween above frees
# it in DEATH_FADE_DURATION, well before the zones' own telegraph_time
# typically resolves). Everything the delayed callback needs is captured into
# plain local closures up front (host node, positions, multiplier) -- it must
# never reference `self`, since `self` won't be valid by the time it runs.
func _spawn_volatile_death_zones() -> void:
	var m: Dictionary = MUTATIONS["volatile"]
	var tree := get_tree()
	if not is_instance_valid(tree) or not is_instance_valid(tree.current_scene):
		return
	var host: Node = tree.current_scene
	var zone_count: int = m["zone_count"]
	var zone_radius: float = m["zone_radius"]
	var telegraph_time: float = m["telegraph_time"]
	var damage: float = m["zone_damage"]
	var color: Color = m["color"]
	var dmg_mult := _damage_mult
	var points: Array[Vector2] = []
	for _i in zone_count:
		points.append(global_position + Vector2(randf_range(-70.0, 70.0), randf_range(-50.0, 50.0)))
	for p in points:
		Telegraph.show_circle(p, zone_radius, color, telegraph_time, host)
	tree.create_timer(telegraph_time, false).timeout.connect(func():
		if not is_instance_valid(host):
			return
		var player := host.get_tree().get_first_node_in_group("player")
		for p in points:
			ImpactVFX.flash_burst(p, zone_radius, Color(color.r, color.g, color.b, 1.0), host)
			if is_instance_valid(player) and player.has_method("take_damage") and player.global_position.distance_to(p) <= zone_radius:
				player.take_damage(damage * dmg_mult)
	)


func _run_attack_loop() -> void:
	# process_always=false on every timer in this loop -- without it, Godot's
	# default (true) keeps these counting down in real time even while
	# get_tree().paused is set by the Pause Menu, so the boss would keep
	# telegraphing and landing hits on a "paused" screen.
	await get_tree().create_timer(INITIAL_ATTACK_DELAY, false).timeout
	while _attack_loop_running and is_instance_valid(self):
		if not _engaged:
			await get_tree().create_timer(0.5, false).timeout
			continue
		var pool: Array = _phase_1_attacks if current_phase == 1 else _phase_2_attacks
		var attack_id: String = pool[randi() % pool.size()]
		await _execute_attack(attack_id)


func _execute_attack(attack_id: String) -> void:
	match attack_id:
		"summon_saplings":
			_summon_saplings()
			await get_tree().create_timer(SUMMON_COOLDOWN * _cooldown_mult, false).timeout
			return
		"rapid_volley":
			await _rapid_volley()
			return
		"arrow_rain":
			await _arrow_rain()
			return
		"shadow_step":
			await _shadow_step()
			return
		"throw_rock":
			await _throw_rock()
			return
		"charge":
			await _charge()
			return
		"leap_smash":
			await _leap_smash()
			return
		"summon_flames":
			await _summon_flames()
			return
	var info: Dictionary = _pattern["attacks"][attack_id]
	SignalBus.boss_attack_telegraph.emit()

	var player := get_tree().get_first_node_in_group("player")
	var target_pos := Vector2.ZERO
	if is_instance_valid(player):
		target_pos = player.global_position

	_pause_walk_for_attack()
	_show_telegraph(info, target_pos)
	_play_attack_lunge(target_pos, info["telegraph_time"])
	await get_tree().create_timer(info["telegraph_time"], false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	_apply_attack_damage(attack_id, info, target_pos)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(info["cooldown"] * _cooldown_mult, false).timeout


func _apply_attack_damage(attack_id: String, info: Dictionary, target_pos: Vector2) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("take_damage"):
		return

	var hit := false
	var flash_pos := target_pos
	var flash_radius: float = IMPACT_FLASH_RADIUS
	match info["shape"]:
		"player_circle":
			flash_radius = info["radius"]
			if player.global_position.distance_to(target_pos) <= info["radius"]:
				hit = true
		"self_circle":
			flash_pos = global_position
			flash_radius = info["radius"]
			if player.global_position.distance_to(global_position) <= info["radius"]:
				hit = true
		"reach_line":
			flash_pos = (global_position + target_pos) / 2.0
			var poly := _rect_polygon(global_position, target_pos, info["width"])
			if Geometry2D.is_point_in_polygon(player.global_position, poly):
				hit = true
	# A real effect where the telegraph resolves, instead of the warning shape
	# just silently vanishing. (2026-07-16) Every attack used to share the
	# exact same flash_burst() ring regardless of what it actually was --
	# each one now gets its own distinct procedural shape matching its
	# identity (see the "Boss attacks" section of impact_vfx.gd); flash_burst
	# stays as the fallback for anything not special-cased below.
	var flash_color: Color = info["color"]
	match attack_id:
		"root_slam":
			ImpactVFX.ground_spikes(flash_pos, flash_radius, self)
		"vine_whip":
			ImpactVFX.whip_lash(global_position, target_pos, self)
		"poison_burst":
			ImpactVFX.poison_cloud(flash_pos, flash_radius, self)
		"aimed_shot":
			ImpactVFX.arrow_shot(global_position, target_pos, self)
		"sword_slash":
			ImpactVFX.sword_slash(flash_pos, (target_pos - global_position).normalized(), self)
		"shockwave":
			ImpactVFX.ground_shockwave(flash_pos, flash_radius, self)
		"shield_burst":
			ImpactVFX.shield_flash(flash_pos, flash_radius, self)
		"claw_swipe":
			ImpactVFX.claw_swipe(flash_pos, (target_pos - global_position).normalized(), self)
		"fire_breath":
			ImpactVFX.fire_explosion(flash_pos, flash_radius, self)
		_:
			ImpactVFX.flash_burst(flash_pos, flash_radius, Color(flash_color.r, flash_color.g, flash_color.b, 1.0), self)
	if hit:
		player.take_damage(info["damage"] * _damage_mult)


func _show_telegraph(info: Dictionary, target_pos: Vector2) -> void:
	var shape := Polygon2D.new()
	shape.color = info["color"]
	match info["shape"]:
		"player_circle":
			shape.polygon = _circle_polygon(info["radius"])
			shape.global_position = target_pos
		"self_circle":
			shape.polygon = _circle_polygon(info["radius"])
			shape.global_position = global_position
		"reach_line":
			shape.polygon = _rect_polygon(global_position, target_pos, info["width"])
	get_tree().current_scene.add_child(shape)
	var duration: float = info["telegraph_time"]
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


func _summon_saplings() -> void:
	if sapling_data == null:
		return
	var wm := get_tree().get_first_node_in_group("wave_manager")
	for _i in SAPLING_COUNT:
		var enemy = sapling_data.scene.instantiate()
		enemy.setup(sapling_data)  # BEFORE add_child, per the existing contract
		enemy._is_wave_tracked = false  # a boss add, not part of the wave's own spawn queue -- must never affect wave-clear
		enemy.global_position = global_position + Vector2(randf_range(-60.0, 60.0), 30.0 + randf_range(0.0, 20.0))
		enemy.modulate = Color(0.4, 0.8, 0.4, 1.0)
		get_tree().current_scene.add_child(enemy)
		# (2026-07-17) activate() now does the per-life init _ready() used to
		# do automatically (current_hp, movement/attack behavior on_ready(),
		# sprite playback) -- see enemy_base.gd. Must be called explicitly
		# here since minions never go through EnemySpawner.spawn().
		enemy.activate()
		if is_instance_valid(wm):
			enemy.died.connect(wm._on_minion_died)


# Corrupted Forest Guardian's ranged option -- a real thrown rock (procedural
# Polygon2D, no rock art exists anywhere in the project) rather than another
# static telegraphed zone, so the golem has a threat that works even before
# it's close enough for root_slam/vine_whip's melee-range shapes to matter.
func _throw_rock() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var player := get_tree().get_first_node_in_group("player")
	var target_pos: Vector2 = player.global_position if is_instance_valid(player) else global_position
	_pause_walk_for_attack()
	# (2026-07-20) Duration covers telegraph+flight, not just telegraph -- it
	# used to vanish the instant the throw began, leaving the impact zone
	# live but invisible for the whole flight, which is exactly what made an
	# evade "still get hit" per direct user report.
	_show_circle_telegraph(target_pos, THROW_ROCK_IMPACT_RADIUS, THROW_ROCK_TELEGRAPH_COLOR, THROW_ROCK_TELEGRAPH_TIME + THROW_ROCK_FLIGHT_TIME)
	_play_attack_lunge(target_pos, THROW_ROCK_TELEGRAPH_TIME)
	var throw_origin := global_position
	await get_tree().create_timer(THROW_ROCK_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	await _fly_rock(throw_origin, target_pos)
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("take_damage") and player.global_position.distance_to(target_pos) <= THROW_ROCK_IMPACT_RADIUS:
		player.take_damage(THROW_ROCK_DAMAGE * _damage_mult)
	ImpactVFX.flash_burst(target_pos, THROW_ROCK_IMPACT_RADIUS, Color(THROW_ROCK_COLOR.r, THROW_ROCK_COLOR.g, THROW_ROCK_COLOR.b, 1.0), self)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(THROW_ROCK_COOLDOWN * _cooldown_mult, false).timeout


# Arcs the rock up then down across two chained tween segments (a rough
# parabola) instead of a straight line to the target, so it reads as thrown
# rather than sliding/teleporting diagonally.
func _fly_rock(from_pos: Vector2, to_pos: Vector2) -> void:
	var rock := Polygon2D.new()
	rock.color = THROW_ROCK_COLOR
	rock.polygon = _rock_polygon()
	rock.global_position = from_pos
	get_tree().current_scene.add_child(rock)
	var peak_pos: Vector2 = from_pos.lerp(to_pos, 0.5) + Vector2(0, -THROW_ROCK_ARC_HEIGHT)
	var tween := rock.create_tween()
	tween.tween_property(rock, "global_position", peak_pos, THROW_ROCK_FLIGHT_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(rock, "global_position", to_pos, THROW_ROCK_FLIGHT_TIME * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(rock, "rotation", TAU * 1.2, THROW_ROCK_FLIGHT_TIME)
	await tween.finished
	if is_instance_valid(rock):
		rock.queue_free()


func _rock_polygon() -> PackedVector2Array:
	# (2026-07-20) Scaled ~1.4x from the original (-8,-6)..(-9,3) points per
	# direct user report that the flying rock is hard to see in flight.
	return PackedVector2Array([
		Vector2(-11, -8), Vector2(6, -13), Vector2(13, -3),
		Vector2(10, 8), Vector2(-4, 13), Vector2(-13, 4),
	])


# Dark Ranger Commander -- fires a fan of real (pooled) projectiles rather
# than a static telegraphed zone, since an archer boss should visibly shoot
# arrows. Reuses CursedBolt.tscn (already collision-configured to hit the
# player layer) and ProjectilePool, same infrastructure RangedAttack-based
# enemies already use.
func _rapid_volley() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var player := get_tree().get_first_node_in_group("player")
	_pause_walk_for_attack()
	if is_instance_valid(player):
		_play_attack_lunge(player.global_position, RAPID_VOLLEY_TELEGRAPH_TIME)
	await get_tree().create_timer(RAPID_VOLLEY_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running or not is_instance_valid(player):
		_resume_walk_for_cooldown()
		await get_tree().create_timer(RAPID_VOLLEY_COOLDOWN * _cooldown_mult, false).timeout
		return
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if is_instance_valid(pool):
		for i in RAPID_VOLLEY_SHOT_COUNT:
			var angle_offset := deg_to_rad(RAPID_VOLLEY_SPREAD_DEG * (i - float(RAPID_VOLLEY_SHOT_COUNT - 1) / 2.0))
			var dir := base_dir.rotated(angle_offset)
			var proj = pool.acquire(RAPID_VOLLEY_PROJECTILE)
			proj.activate(dir, RAPID_VOLLEY_SPEED, RAPID_VOLLEY_DAMAGE * _damage_mult, global_position, 0, "player", RAPID_VOLLEY_MAX_RANGE)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(RAPID_VOLLEY_COOLDOWN * _cooldown_mult, false).timeout


# Dark Ranger Commander -- several telegraphed impact zones scattered around
# the player's position (landing together), instead of Forest Guardian's
# single centered zone -- reads as "raining down" rather than "one big hit."
# Shared by _arrow_rain()/_summon_flames(): N telegraphed circular zones
# scattered around the player's position, landing together in one resolve
# moment. `resolve_vfx` takes a single Vector2 point and plays whatever
# impact visual that attack uses there (kept per-attack since the two use
# genuinely different ImpactVFX calls, not just different colors).
func _scattered_zone_attack(zone_count: int, zone_radius: float, telegraph_time: float, cooldown: float, damage: float, telegraph_color: Color, resolve_vfx: Callable) -> void:
	SignalBus.boss_attack_telegraph.emit()
	var player := get_tree().get_first_node_in_group("player")
	var center: Vector2 = player.global_position if is_instance_valid(player) else global_position
	var points: Array[Vector2] = []
	for _i in zone_count:
		points.append(center + Vector2(randf_range(-90.0, 90.0), randf_range(-60.0, 60.0)))
	for p in points:
		_show_circle_telegraph(p, zone_radius, telegraph_color, telegraph_time)
	_pause_walk_for_attack()
	_play_attack_lunge(center, telegraph_time)
	await get_tree().create_timer(telegraph_time, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	for p in points:
		resolve_vfx.call(p)
	player = get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		for p in points:
			if player.global_position.distance_to(p) <= zone_radius:
				player.take_damage(damage * _damage_mult)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(cooldown * _cooldown_mult, false).timeout


func _arrow_rain() -> void:
	await _scattered_zone_attack(
		ARROW_RAIN_IMPACT_COUNT, ARROW_RAIN_IMPACT_RADIUS, ARROW_RAIN_TELEGRAPH_TIME, ARROW_RAIN_COOLDOWN, ARROW_RAIN_DAMAGE, ARROW_RAIN_COLOR,
		func(p: Vector2): ImpactVFX.flash_burst(p, ARROW_RAIN_IMPACT_RADIUS, Color(ARROW_RAIN_COLOR.r, ARROW_RAIN_COLOR.g, ARROW_RAIN_COLOR.b, 1.0), self)
	)


# Dark Ranger Commander -- a short fade-out/reposition/fade-in "teleport",
# matching the doc's "short teleport or dash" without needing new VFX art.
func _shadow_step() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var fade_tween := create_tween()
	fade_tween.tween_property(sprite, "modulate:a", 0.0, SHADOW_STEP_FADE_TIME)
	await fade_tween.finished
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	global_position.x = clampf(global_position.x + randf_range(-SHADOW_STEP_RANGE, SHADOW_STEP_RANGE), SHADOW_STEP_MIN_X, SHADOW_STEP_MAX_X)
	var fade_in_tween := create_tween()
	fade_in_tween.tween_property(sprite, "modulate:a", _base_modulate.a, SHADOW_STEP_FADE_TIME)
	var cam := get_viewport().get_camera_2d()
	if is_instance_valid(cam) and cam.has_method("shake"):
		cam.shake(4.0, 0.15)
	await get_tree().create_timer(SHADOW_STEP_COOLDOWN * _cooldown_mult, false).timeout


# Fallen Knight -- a short horizontal dash toward the player, ending in a
# sword strike (reuses ImpactVFX.sword_slash() for the landing hit). Unlike
# every other special-cased attack, this one actually moves the boss node
# itself (a tween on global_position), not just a static hitbox -- capped to
# CHARGE_DISTANCE and horizontal-only so it can never overshoot into (or
# interact with) the post-engage advance-to-lose-line creep.
# Shared by _charge()/_leap_smash(): both are a bounded, horizontal-only
# reposition toward wherever the player currently is, clamped to the same
# play-area bounds SHADOW_STEP_MIN_X/MAX_X already established -- the two
# attacks' telegraph shape, hit-check, and landing VFX differ (corridor vs
# circle) and stay in each attack's own function.
func _compute_horizontal_dash_target(distance: float) -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	var dir_x := 1.0
	if is_instance_valid(player) and player.global_position.x < global_position.x:
		dir_x = -1.0
	var origin := global_position
	var end := Vector2(clampf(origin.x + dir_x * distance, SHADOW_STEP_MIN_X, SHADOW_STEP_MAX_X), origin.y)
	return {"origin": origin, "end": end, "dir_x": dir_x}


func _charge() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var target := _compute_horizontal_dash_target(CHARGE_DISTANCE)
	var charge_origin: Vector2 = target["origin"]
	var charge_end: Vector2 = target["end"]
	var dir_x: float = target["dir_x"]
	_pause_walk_for_attack()
	# (2026-07-20) Same readability fix as _throw_rock(): stay visible through
	# the dash itself, not just the telegraph window before it.
	_show_line_telegraph(charge_origin, charge_end, CHARGE_HIT_WIDTH, Color(CHARGE_COLOR.r, CHARGE_COLOR.g, CHARGE_COLOR.b, 0.5), CHARGE_TELEGRAPH_TIME + CHARGE_DASH_TIME)
	_play_attack_lunge(charge_end, CHARGE_TELEGRAPH_TIME)
	await get_tree().create_timer(CHARGE_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	var dash_tween := create_tween()
	dash_tween.tween_property(self, "global_position", charge_end, CHARGE_DASH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await dash_tween.finished
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	var player := get_tree().get_first_node_in_group("player")
	# Reuses the exact same corridor polygon as the telegraph -- matching
	# every other reach_line attack's own telegraph-equals-hitbox convention
	# (see _apply_attack_damage()'s "reach_line" branch) -- instead of a
	# separate endpoint-only circle, which let a player standing outside the
	# telegraphed corridor near charge_end still take a hidden hit, while a
	# player standing inside the telegraphed corridor's middle took none.
	var charge_poly := _rect_polygon(charge_origin, charge_end, CHARGE_HIT_WIDTH)
	if is_instance_valid(player) and player.has_method("take_damage") and Geometry2D.is_point_in_polygon(player.global_position, charge_poly):
		player.take_damage(CHARGE_DAMAGE * _damage_mult)
	ImpactVFX.sword_slash(global_position, Vector2(dir_x, 0.0), self)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(CHARGE_COOLDOWN * _cooldown_mult, false).timeout


# Demon Beast -- "jumps to a target area": leaps horizontally (same bounded,
# horizontal-only reposition as _charge(), same reasoning) and lands as an
# AoE circle instead of a corridor. Telegraph and hit-check are both the
# same circle centered on the landing point, so unlike the original Charge
# implementation there's no shape mismatch to introduce here.
func _leap_smash() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var target := _compute_horizontal_dash_target(LEAP_SMASH_DISTANCE)
	var jump_end: Vector2 = target["end"]
	_pause_walk_for_attack()
	# (2026-07-20) Same readability fix as _throw_rock(): stay visible through
	# the jump itself, not just the telegraph window before it.
	_show_circle_telegraph(jump_end, LEAP_SMASH_RADIUS, Color(LEAP_SMASH_COLOR.r, LEAP_SMASH_COLOR.g, LEAP_SMASH_COLOR.b, 0.5), LEAP_SMASH_TELEGRAPH_TIME + LEAP_SMASH_JUMP_TIME)
	_play_attack_lunge(jump_end, LEAP_SMASH_TELEGRAPH_TIME)
	await get_tree().create_timer(LEAP_SMASH_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	var jump_tween := create_tween()
	jump_tween.tween_property(self, "global_position", jump_end, LEAP_SMASH_JUMP_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await jump_tween.finished
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("take_damage") and player.global_position.distance_to(global_position) <= LEAP_SMASH_RADIUS:
		player.take_damage(LEAP_SMASH_DAMAGE * _damage_mult)
	ImpactVFX.ground_shockwave(global_position, LEAP_SMASH_RADIUS, self)
	_resume_walk_for_cooldown()
	await get_tree().create_timer(LEAP_SMASH_COOLDOWN * _cooldown_mult, false).timeout


# Demon Beast -- several telegraphed fire zones scattered around the player's
# position (landing together), same shape as Dark Ranger's _arrow_rain(),
# just fire-themed (reuses ImpactVFX.fire_explosion(), no new VFX needed).
func _summon_flames() -> void:
	await _scattered_zone_attack(
		SUMMON_FLAMES_ZONE_COUNT, SUMMON_FLAMES_ZONE_RADIUS, SUMMON_FLAMES_TELEGRAPH_TIME, SUMMON_FLAMES_COOLDOWN, SUMMON_FLAMES_DAMAGE, SUMMON_FLAMES_COLOR,
		func(p: Vector2): ImpactVFX.fire_explosion(p, SUMMON_FLAMES_ZONE_RADIUS, self)
	)


func _show_circle_telegraph(pos: Vector2, radius: float, color: Color, duration: float) -> void:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _circle_polygon(radius)
	shape.global_position = pos
	get_tree().current_scene.add_child(shape)
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


func _show_line_telegraph(from_pos: Vector2, to_pos: Vector2, width: float, color: Color, duration: float) -> void:
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _rect_polygon(from_pos, to_pos, width)
	get_tree().current_scene.add_child(shape)
	get_tree().create_timer(duration, false).timeout.connect(func():
		if is_instance_valid(shape):
			shape.queue_free()
	)


func _circle_polygon(radius: float, segments: int = 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


func _rect_polygon(from_point: Vector2, to_point: Vector2, width: float) -> PackedVector2Array:
	var dir := (to_point - from_point).normalized()
	var normal := Vector2(-dir.y, dir.x) * (width / 2.0)
	return PackedVector2Array([from_point + normal, to_point + normal, to_point - normal, from_point - normal])
