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

# Each boss picks a named entry via @export var attack_pattern_id below --
# one shared script serves every boss (telegraph/phase/death framework is
# 100% generic), only the attack kit itself differs per boss. Attacks not
# listed in "generic" (i.e. not backed by the shape-based telegraph system
# in _execute_attack/_apply_attack_damage/_show_telegraph) are special-cased
# by id in _execute_attack() instead -- same pattern the original
# "summon_saplings" always used, just no longer the only one.
const ATTACK_PATTERNS := {
	"forest_guardian": {
		"phase_1": ["root_slam", "vine_whip"],
		"phase_2": ["poison_burst", "summon_saplings"],
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
}
const PHASE2_HP_RATIO := 0.5
const SUMMON_COOLDOWN := 5.0
const SAPLING_COUNT := 3
const INITIAL_ATTACK_DELAY := 1.5

# Dark Ranger Commander's special-cased (non-generic-shape) attacks.
const RAPID_VOLLEY_PROJECTILE := preload("res://scenes/effects/CursedBolt.tscn")
const RAPID_VOLLEY_DAMAGE := 1.0  # (2026-07-16) 7.0->1.0, rescaled with player.max_hp's 100->10 rebalance (effective 2 per bolt after BOSS_DAMAGE_MULT)
const RAPID_VOLLEY_SHOT_COUNT := 3
const RAPID_VOLLEY_SPREAD_DEG := 18.0
const RAPID_VOLLEY_SPEED := 260.0
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

@export var engage_y: float = 400.0
@export var sapling_data: EnemyData
@export var attack_pattern_id: String = "forest_guardian"

@onready var sprite: AnimatedSprite2D = $Sprite

signal died(xp_reward: int, drop_chance: float, death_position: Vector2)

var data: EnemyData
var current_hp: float
var _max_hp: float
var current_phase := 1
var _engaged := false
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
	velocity = Vector2(0, data.base_speed * _speed_mult)
	_base_modulate = sprite.modulate
	_base_scale = sprite.scale
	_sprite_base_position = sprite.position
	sprite.play("move")
	_attack_loop_running = true
	SignalBus.boss_hp_changed.emit(current_hp, _max_hp)
	_run_attack_loop()


func _physics_process(delta: float) -> void:
	StatusEffects.tick(self, delta)
	if not is_instance_valid(self):
		return  # a Fire DOT tick can kill the boss mid-frame
	if _engaged:
		return
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


func apply_status(element: String, duration: float) -> void:
	StatusEffects.apply(self, element, duration)


func take_damage(amount: float) -> void:
	if _is_dying:
		return
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
	_lunge_tween.chain().tween_callback(func():
		if is_instance_valid(self) and _engaged:
			_start_idle_bob()
	)


func _die() -> void:
	if _is_dying:
		return
	_is_dying = true
	_attack_loop_running = false
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
			await get_tree().create_timer(SUMMON_COOLDOWN, false).timeout
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
	var info: Dictionary = _pattern["attacks"][attack_id]
	SignalBus.boss_attack_telegraph.emit()
	
	var player := get_tree().get_first_node_in_group("player")
	var target_pos := Vector2.ZERO
	if is_instance_valid(player):
		target_pos = player.global_position
		
	_show_telegraph(info, target_pos)
	_play_attack_lunge(target_pos, info["telegraph_time"])
	await get_tree().create_timer(info["telegraph_time"], false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	_apply_attack_damage(info, target_pos)
	await get_tree().create_timer(info["cooldown"], false).timeout


func _apply_attack_damage(info: Dictionary, target_pos: Vector2) -> void:
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
	# A real flash where the telegraph resolves, instead of the warning shape
	# just silently vanishing -- reuses the same ImpactVFX the player's own
	# skills already use, so boss attacks land with a comparable "real effect".
	var flash_color: Color = info["color"]
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
		enemy.setup(sapling_data)  # BEFORE add_child — _ready() reads data synchronously
		enemy._is_wave_tracked = false  # a boss add, not part of the wave's own spawn queue -- must never affect wave-clear
		enemy.global_position = global_position + Vector2(randf_range(-60.0, 60.0), 30.0 + randf_range(0.0, 20.0))
		enemy.modulate = Color(0.4, 0.8, 0.4, 1.0)
		get_tree().current_scene.add_child(enemy)
		if is_instance_valid(wm):
			enemy.died.connect(wm._on_minion_died)


# Dark Ranger Commander -- fires a fan of real (pooled) projectiles rather
# than a static telegraphed zone, since an archer boss should visibly shoot
# arrows. Reuses CursedBolt.tscn (already collision-configured to hit the
# player layer) and ProjectilePool, same infrastructure RangedAttack-based
# enemies already use.
func _rapid_volley() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_play_attack_lunge(player.global_position, RAPID_VOLLEY_TELEGRAPH_TIME)
	await get_tree().create_timer(RAPID_VOLLEY_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running or not is_instance_valid(player):
		await get_tree().create_timer(RAPID_VOLLEY_COOLDOWN, false).timeout
		return
	var base_dir: Vector2 = (player.global_position - global_position).normalized()
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if is_instance_valid(pool):
		for i in RAPID_VOLLEY_SHOT_COUNT:
			var angle_offset := deg_to_rad(RAPID_VOLLEY_SPREAD_DEG * (i - float(RAPID_VOLLEY_SHOT_COUNT - 1) / 2.0))
			var dir := base_dir.rotated(angle_offset)
			var proj = pool.acquire(RAPID_VOLLEY_PROJECTILE)
			proj.activate(dir, RAPID_VOLLEY_SPEED, RAPID_VOLLEY_DAMAGE * _damage_mult, global_position, 0, "player", RAPID_VOLLEY_MAX_RANGE)
	await get_tree().create_timer(RAPID_VOLLEY_COOLDOWN, false).timeout


# Dark Ranger Commander -- several telegraphed impact zones scattered around
# the player's position (landing together), instead of Forest Guardian's
# single centered zone -- reads as "raining down" rather than "one big hit."
func _arrow_rain() -> void:
	SignalBus.boss_attack_telegraph.emit()
	var player := get_tree().get_first_node_in_group("player")
	var center: Vector2 = player.global_position if is_instance_valid(player) else global_position
	var points: Array[Vector2] = []
	for _i in ARROW_RAIN_IMPACT_COUNT:
		points.append(center + Vector2(randf_range(-90.0, 90.0), randf_range(-60.0, 60.0)))
	for p in points:
		_show_circle_telegraph(p, ARROW_RAIN_IMPACT_RADIUS, ARROW_RAIN_COLOR, ARROW_RAIN_TELEGRAPH_TIME)
	_play_attack_lunge(center, ARROW_RAIN_TELEGRAPH_TIME)
	await get_tree().create_timer(ARROW_RAIN_TELEGRAPH_TIME, false).timeout
	if not is_instance_valid(self) or not _attack_loop_running:
		return
	for p in points:
		ImpactVFX.flash_burst(p, ARROW_RAIN_IMPACT_RADIUS, Color(ARROW_RAIN_COLOR.r, ARROW_RAIN_COLOR.g, ARROW_RAIN_COLOR.b, 1.0), self)
	if is_instance_valid(player):
		for p in points:
			if player.global_position.distance_to(p) <= ARROW_RAIN_IMPACT_RADIUS:
				player.take_damage(ARROW_RAIN_DAMAGE * _damage_mult)
	await get_tree().create_timer(ARROW_RAIN_COOLDOWN, false).timeout


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
	await get_tree().create_timer(SHADOW_STEP_COOLDOWN, false).timeout


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
