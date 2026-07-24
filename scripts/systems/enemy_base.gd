extends CharacterBody2D
class_name EnemyBase

const CONTACT_DAMAGE_INTERVAL := 0.6
const HIT_FLASH_DURATION := 0.08
const HIT_PUNCH_SCALE := 1.2
const ATTACK_LUNGE_OFFSET := 4.0
const ATTACK_LUNGE_DURATION := 0.1
const DEATH_FADE_DURATION := 0.25
const LEAK_DAMAGE := 1.0  # HP cost when an enemy crosses the lose line without being killed

# (2026-07-24) Enemies PASS THROUGH the player -- EnemyBase.tscn's root body
# carries collision_mask = 0 rather than 1, and this is load-bearing gameplay,
# not a physics tidy-up.
#
# With mask = 1 the player's 32px body was a solid wall: measured, an enemy
# walking down the player's lane stopped dead at y=1102 (1150 - 32 - 16) and
# stayed there forever, grinding off 15 HP in 9 seconds of contact ticks while
# never reaching the lose line at 1215. That made contact damage the real
# threat, made body-blocking a lane a viable strategy, and made the lose line
# unreachable in whichever lane the player stood in.
#
# Per user, the lose line is the threat instead: an enemy that gets past you
# should cost you the line, not park on you. Contact still hurts on the way
# through, because the Hurtbox Area2D keeps its own collision_mask = 1 -- only
# the physical body stops colliding. Bosses are unaffected either way: they
# stop at BossBase.LOSE_LINE_Y (950), 200px above the player, so they never
# reached the player's body to begin with.

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hurtbox: Area2D = $Hurtbox
@onready var contact_timer: Timer = $ContactDamageTimer
@onready var attack_timer: Timer = $AttackTimer
@onready var collision: CollisionShape2D = $Collision

var data: EnemyData
var current_hp: float
var _player_in_contact: Node2D = null
var _hp_mult := 1.0
var _speed_mult := 1.0
var _damage_mult := 1.0
var _xp_override := -1  # -1 sentinel = "use data.xp_reward unmodified"
var _time_alive := 0.0
var _is_wave_tracked := true  # false for boss-summoned minions -- must never affect wave-clear accounting
# (2026-07-17) Set true only by EnemySpawner when this instance came from a
# real EnemyPool -- gates whether _finish_life() returns it to the pool or
# frees it outright. Boss-summoned minions (instantiated directly, never
# through the spawner) stay false and always free normally.
var _pooled := false

var _base_modulate: Color
# (2026-07-17) The ROOT node's own authored tint (e.g. ShieldSkeleton/
# StoneGolem/ArmoredBrute's blue/orange/red .tscn-baked modulate), distinct
# from `_base_modulate` above which tracks the SPRITE child's own modulate.
# Captured once here so EnemySpawner can restore it on every non-elite
# spawn instead of hardcoding Color.WHITE, which would erase any species'
# intentional tint.
var _base_root_modulate: Color
var _base_scale: Vector2
var _hit_tween: Tween
var _lunge_tween: Tween
var _is_dying := false
var status: Dictionary = {}  # element name (StatusEffects.FIRE/LIGHTNING/FROST) -> seconds remaining
var _base_velocity: Vector2 = Vector2.ZERO  # velocity as the movement behavior last set it, before any status scaling

signal died(xp_reward: int, drop_chance: float, death_position: Vector2)


func setup(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1) -> void:
	data = enemy_data  # caller MUST call this before add_child()
	_hp_mult = hp_mult
	_speed_mult = speed_mult
	_damage_mult = damage_mult
	_xp_override = xp_override


func _ready() -> void:
	# One-time setup only -- pooled instances are reused across many lives
	# without _ready() running again (same convention as projectile.gd's own
	# pooling), so anything that depends on `data` or needs resetting per
	# life belongs in activate(), not here. Group membership in particular
	# must NOT be a one-time add here -- see activate()/_deactivate().
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	contact_timer.wait_time = CONTACT_DAMAGE_INTERVAL
	contact_timer.timeout.connect(_on_contact_timer_timeout)
	_base_modulate = sprite.modulate
	_base_root_modulate = modulate
	_base_scale = sprite.scale


func activate() -> void:
	# Re-primes every per-life state -- called once for a brand new spawn and
	# again every time a pooled instance is reused. `data`/the multiplier
	# vars must already be set via setup() before this runs.
	# (2026-07-17) add_to_group() is safe to call even if already a member --
	# this is the fix for a real bug: a pooled enemy that died was NEVER
	# removed from "enemy", so every targeting/splash/chain query across the
	# game (player.gd's nearest-enemy aim, burst/chain damage, the danger
	# indicator, status-effect spread) kept finding dead, invisible, pooled
	# enemies indefinitely -- the player would aim and fire at a dead
	# enemy's last position, landing no hit and no visual feedback, reading
	# exactly like "attacks nothing" right after a kill.
	add_to_group("enemy")
	current_hp = data.base_hp * _hp_mult
	_is_dying = false
	_time_alive = 0.0
	status.clear()
	_player_in_contact = null
	contact_timer.stop()
	attack_timer.stop()
	collision.disabled = false
	hurtbox.set_deferred("monitoring", true)
	sprite.modulate = _base_modulate
	sprite.scale = _base_scale
	sprite.position = Vector2.ZERO
	visible = true
	set_physics_process(true)
	if data.movement_behavior:
		data.movement_behavior.on_ready(self)
	_base_velocity = velocity
	sprite.play("move")
	if data.attack_behavior:
		data.attack_behavior.on_ready(self)


func _physics_process(delta: float) -> void:
	_time_alive += delta
	StatusEffects.tick(self, delta)
	if not is_instance_valid(self):
		return  # a Fire DOT tick can kill the enemy mid-frame
	# Restore the un-scaled velocity before the movement behavior runs, or a
	# Frost/Lightning multiplier applied last frame would compound every frame
	# instead of holding steady -- straight/dive movement only ever set
	# velocity once in on_ready() and never touch it again, so without this
	# reset a slow effect would silently decay toward zero within a few frames.
	velocity = _base_velocity
	if data.movement_behavior:
		data.movement_behavior.physics_process(self, delta)
	_base_velocity = velocity
	# A Frost freeze or the opening moment of a shock (LIGHTNING_STUN_DURATION)
	# is an absolute stop -- unlike the slow below it can't be eroded by wave
	# speed scaling, so a shock still reads as a real hit at any wave.
	if StatusEffects.is_frozen(self) or StatusEffects.is_stunned(self):
		velocity = Vector2.ZERO
	else:
		velocity *= StatusEffects.speed_multiplier(self)
	move_and_slide()
	# (2026-07-24) Checked here, right after the move that could have carried it
	# across, rather than via VisibleOnScreenNotifier2D -- see lose_line.gd for
	# why that notifier was the wrong trigger for a rule that costs the player HP.
	if global_position.y >= LoseLine.Y:
		_cross_lose_line()


func apply_status(element: String, duration: float) -> void:
	StatusEffects.apply(self, element, duration)


func take_damage(amount: float, _element: String = "") -> void:
	# _element is accepted-but-ignored: only BossBase's affinity system (see
	# boss_base.gd) reads it, but the two classes share every damage call site
	# (projectiles, area strikes, DOT ticks all hit the "enemy" group), so the
	# signatures must stay compatible.
	if _is_dying:
		return
	current_hp -= amount * StatusEffects.damage_amp(self)  # Brittle Frost: frozen enemies take extra damage
	SignalBus.enemy_hit.emit()
	if current_hp <= 0.0:
		_die()
	else:
		_play_hit_reaction()


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


func _play_attack_lunge() -> void:
	if _lunge_tween:
		_lunge_tween.kill()
	sprite.position = Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player")
	var lunge_dir := Vector2.DOWN
	if is_instance_valid(player):
		lunge_dir = (player.global_position - global_position).normalized()
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(sprite, "position", lunge_dir * ATTACK_LUNGE_OFFSET, ATTACK_LUNGE_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(sprite, "position", Vector2.ZERO, ATTACK_LUNGE_DURATION * 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_hurtbox_body_entered(body: Node) -> void:
	# (2026-07-24) Touching the player hurts, for EVERY species -- this used to
	# be delegated entirely to the attack behavior, so it only happened for
	# ContactAttack. RangedAttack inherits AttackBehavior's do-nothing
	# on_contact(), which meant the Cursed Wraith (the game's only ranged
	# monster, and a flying one) could fly straight through the player dealing
	# literally zero damage -- the "hit by a flying monster and HP doesn't move"
	# report. Living here rather than in a behavior also means a future behavior
	# can't silently opt out of it by forgetting to implement on_contact().
	if not (body.is_in_group("player") and body.has_method("take_damage")):
		return
	_player_in_contact = body
	body.take_damage(contact_damage())
	contact_timer.start()
	_play_attack_lunge()
	if data.attack_behavior:
		data.attack_behavior.on_contact(self, body)  # behavior-specific extras only


func _on_hurtbox_body_exited(body: Node) -> void:
	if body == _player_in_contact:
		_player_in_contact = null
		contact_timer.stop()


func _on_contact_timer_timeout() -> void:
	if is_instance_valid(_player_in_contact):
		_player_in_contact.take_damage(contact_damage())
		_play_attack_lunge()
	if data.attack_behavior:
		data.attack_behavior.on_contact_tick(self)


func contact_damage() -> float:
	return data.base_damage * _damage_mult


func _on_attack_timer_timeout() -> void:
	if data.attack_behavior:
		data.attack_behavior.on_attack_timer_timeout(self)


func _cross_lose_line() -> void:
	# The enemy got past the player. Costs 1 HP and ends this life -- per user:
	# "when enemy run over character line, reduce character hp ... and when enemy
	# run pass this line, remove this enemy too".
	#
	# _is_dying doubles as a general "this life is already over" guard: the check
	# that calls this runs every physics frame, so without it a single enemy
	# sitting past the line would bill the player once per frame instead of once,
	# and would double-report to WaveManager. (It also covers the case this guard
	# was originally written for -- an enemy dying on the same frame it crosses.)
	if _is_dying:
		return
	_is_dying = true
	# An enemy that falls past the player without dying still needs to count
	# against the wave's alive tally, or a single escapee permanently blocks
	# notify_enemy_died()'s "_alive_count <= 0" wave-clear check — no XP/drop,
	# just an accounting update so the wave can actually complete. Boss-
	# summoned minions are NOT wave-tracked, so this must stay gated the same
	# way _die()'s signal routing is, or a sapling escaping off-screen would
	# prematurely clear the wave exactly like a killed one would.
	if _is_wave_tracked:
		var wm := get_tree().get_first_node_in_group("wave_manager")
		if is_instance_valid(wm):
			wm.notify_enemy_left_screen()
	# (2026-07-16) Letting an enemy through unpunished made "don't kill
	# everything" a free option -- costs 1 HP regardless of wave-tracking, so
	# even a boss-summoned sapling that slips past still means something.
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("take_damage"):
		player.take_damage(LEAK_DAMAGE)
	# (2026-07-17) A leaked-but-pooled instance used to skip straight to
	# _finish_life() with no deactivation at all, unlike _die() below -- it
	# stayed fully live (movement, hurtbox, attack_timer) while sitting
	# hidden in the pool, so e.g. a leaked ranged enemy kept firing real
	# shots at the player indefinitely until reacquired. Both end-of-life
	# paths now go through the same _deactivate() first.
	_deactivate()
	_finish_life()


func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	StatusEffects.explode_on_death(self)  # Explosive Volley: no-op unless burning and the player has the branch
	var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
	died.emit(xp_reward, data.drop_chance, global_position)
	SignalBus.enemy_died.emit()
	# Stop everything that could still act during the fade-out (the corpse
	# shouldn't keep contact-damaging or firing at the player for the brief
	# window before it's actually removed).
	_deactivate()
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(sprite, "scale", Vector2.ZERO, DEATH_FADE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_DURATION)
	death_tween.chain().tween_callback(_finish_life)


func _deactivate() -> void:
	# Shared by _die() and _cross_lose_line() -- whatever ends this life, it
	# must stop acting immediately: no more contact damage, ranged attacks,
	# or movement, whether it's about to fade out or sit invisible in the
	# pool for an unknown stretch of time before its next life. Leaving the
	# "enemy" group is just as important as the physics/collision/hurtbox
	# state below -- every targeting/splash/chain query in the game finds
	# candidates via that group, so a dead instance left in it stays a valid
	# (if invisible, unhittable) target until reactivate() re-adds it.
	remove_from_group("enemy")
	contact_timer.stop()
	attack_timer.stop()
	hurtbox.set_deferred("monitoring", false)
	# _deactivate() can run synchronously from inside a projectile's
	# body_entered callback (take_damage() -> _die() -> here), which fires
	# while the physics server is still flushing collision queries for this
	# step -- a direct `collision.disabled = true` throws "Can't change this
	# state while flushing queries" in that case, same constraint as
	# hurtbox.monitoring above. Homing elemental shots (2026-07-17) made this
	# path the common case for a kill instead of a rare one, which is what
	# surfaced it.
	collision.set_deferred("disabled", true)
	set_physics_process(false)


func _finish_life() -> void:
	# Disconnect died unconditionally (harmless even for a non-pooled/never-
	# reused instance) -- EnemySpawner.spawn() reconnects it fresh on every
	# acquire, so a stale connection surviving into a pooled instance's next
	# life would double-fire wave-clear/XP rewards on its next death.
	for connection in died.get_connections():
		died.disconnect(connection["callable"])
	visible = false
	if _pooled:
		var pool := get_tree().get_first_node_in_group("enemy_pool")
		if is_instance_valid(pool):
			pool.release(self)
			return
	queue_free()
