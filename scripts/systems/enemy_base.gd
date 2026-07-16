extends CharacterBody2D
class_name EnemyBase

const CONTACT_DAMAGE_INTERVAL := 0.6
const HIT_FLASH_DURATION := 0.08
const HIT_PUNCH_SCALE := 1.2
const ATTACK_LUNGE_OFFSET := 4.0
const ATTACK_LUNGE_DURATION := 0.1
const DEATH_FADE_DURATION := 0.25
const LEAK_DAMAGE := 1.0  # HP cost when an enemy reaches the bottom of the screen without being killed

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hurtbox: Area2D = $Hurtbox
@onready var contact_timer: Timer = $ContactDamageTimer
@onready var screen_check: VisibleOnScreenNotifier2D = $ScreenCheck
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
	# life belongs in activate(), not here.
	add_to_group("enemy")
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	contact_timer.wait_time = CONTACT_DAMAGE_INTERVAL
	contact_timer.timeout.connect(_on_contact_timer_timeout)
	screen_check.screen_exited.connect(_on_screen_exited)
	_base_modulate = sprite.modulate
	_base_scale = sprite.scale


func activate() -> void:
	# Re-primes every per-life state -- called once for a brand new spawn and
	# again every time a pooled instance is reused. `data`/the multiplier
	# vars must already be set via setup() before this runs.
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
	if StatusEffects.is_frozen(self):
		velocity = Vector2.ZERO
	else:
		velocity *= StatusEffects.speed_multiplier(self)
	move_and_slide()


func apply_status(element: String, duration: float) -> void:
	StatusEffects.apply(self, element, duration)


func take_damage(amount: float) -> void:
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
	if data.attack_behavior:
		data.attack_behavior.on_contact(self, body)


func _on_hurtbox_body_exited(body: Node) -> void:
	if body == _player_in_contact:
		_player_in_contact = null
		contact_timer.stop()


func _on_contact_timer_timeout() -> void:
	if data.attack_behavior:
		data.attack_behavior.on_contact_tick(self)


func _on_attack_timer_timeout() -> void:
	if data.attack_behavior:
		data.attack_behavior.on_attack_timer_timeout(self)


func _on_screen_exited() -> void:
	# _is_dying doubles as a general "this life is already over" guard here --
	# a pooled instance gets hidden (visible = false) when it returns to the
	# pool, and VisibleOnScreenNotifier2D can fire screen_exited again purely
	# from that visibility change, not just from actually falling off-screen.
	# Without this guard a just-died enemy could double-report to WaveManager
	# and double-hit the player for leak damage on its own death.
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
	contact_timer.stop()
	attack_timer.stop()
	hurtbox.set_deferred("monitoring", false)
	collision.disabled = true
	set_physics_process(false)
	var death_tween := create_tween()
	death_tween.set_parallel(true)
	death_tween.tween_property(sprite, "scale", Vector2.ZERO, DEATH_FADE_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	death_tween.tween_property(sprite, "modulate:a", 0.0, DEATH_FADE_DURATION)
	death_tween.chain().tween_callback(_finish_life)


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
