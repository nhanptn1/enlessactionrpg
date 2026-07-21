extends Area2D
class_name Projectile

const DEFAULT_MAX_RANGE := 900.0
const CHAIN_RANGE := 220.0  # Chain Spark: max distance to the next chain jump

var direction := Vector2.UP
var speed := 500.0
var damage := 5.0
var pierce_count: int = 0
var target_group: String = "enemy"
var max_range := DEFAULT_MAX_RANGE
var status_rolls: Array[Dictionary] = []  # {element, chance, duration} rolled once per shot by the shooter
var burst_radius: float = 0.0  # 0 = off; guaranteed splash to enemies within this radius of the hit
var chain_count: int = 0  # 0 = off; guaranteed chain to N additional nearest distinct enemies
var burst_vfx_id: String = ""  # "" = element-default burst look (see SkillData.burst_vfx_id)
# null = a plain straight-line shot (unchanged). When set, this shot re-aims
# at the target's current position every physics frame instead of flying its
# initial direction -- a guaranteed hit (barring the target dying or leaving
# max_range first) rather than a one-shot lead prediction that a fast-turning
# target can still dodge. See player.gd::_fire_elemental_projectile().
var homing_target: Node2D = null
var impact_flash_color: Color = Color(0, 0, 0, 0)  # a==0 = off; a bright visual-only flash per hit (class-skill highlight), no splash damage
var impact_flash_radius: float = 0.0
var _hits_remaining: int
var _already_hit: Array[Node] = []
var _spawn_position: Vector2
var _active := false
var _base_visual_scale := Vector2.ONE


func _ready() -> void:
	# Connected once here, never per-activation -- pooled instances are reused
	# without _ready() running again, so re-connecting on every activate()
	# would double (or triple, ...) the signal.
	body_entered.connect(_on_body_entered)
	if has_node("Visual"):
		_base_visual_scale = get_node("Visual").scale


func activate(p_direction: Vector2, p_speed: float, p_damage: float, p_position: Vector2, p_pierce_count: int, p_target_group: String, p_max_range: float = DEFAULT_MAX_RANGE, p_status_rolls: Array[Dictionary] = [], p_burst_radius: float = 0.0, p_chain_count: int = 0, p_visual_scale: float = 1.0, p_burst_vfx_id: String = "", p_homing_target: Node2D = null, p_impact_flash_color: Color = Color(0, 0, 0, 0), p_impact_flash_radius: float = 0.0) -> void:
	direction = p_direction
	speed = p_speed
	damage = p_damage
	pierce_count = p_pierce_count
	target_group = p_target_group
	max_range = p_max_range
	status_rolls = p_status_rolls
	burst_radius = p_burst_radius
	chain_count = p_chain_count
	burst_vfx_id = p_burst_vfx_id
	homing_target = p_homing_target  # pooled reuse -- must reset every activation, not just set-once
	# (2026-07-21) Visual-only highlight for class-skill shots -- a bright
	# per-hit flash (independent of burst_radius, so it adds no splash damage)
	# plus a glow tint on the projectile itself. a==0 means off (basic/
	# elemental shots), which must reset every activation or a pooled shot
	# keeps the previous life's class glow.
	impact_flash_color = p_impact_flash_color
	impact_flash_radius = p_impact_flash_radius
	global_position = p_position
	rotation = direction.angle()
	_spawn_position = p_position
	_hits_remaining = pierce_count + 1  # 0 pierce = 1 total hit, matching prior behavior
	_already_hit.clear()
	_active = true
	visible = true
	set_physics_process(true)
	monitoring = true
	if has_node("Visual"):
		var visual_node = get_node("Visual")
		visual_node.scale = _base_visual_scale * p_visual_scale
		# Brighten toward the flash color for a glow, or reset to white when off.
		visual_node.modulate = Color(1, 1, 1, 1) if impact_flash_color.a <= 0.0 else impact_flash_color.lerp(Color(1, 1, 1, 1), 0.35)
		if visual_node is AnimatedSprite2D:
			visual_node.play()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	# (2026-07-20) is_in_group() check matters as much as is_instance_valid():
	# a pooled enemy's death hides+reuses the node without freeing it (see
	# enemy_base.gd::_deactivate()'s remove_from_group("enemy")), so a dead
	# target stays "valid" forever at its frozen death position. Without this,
	# the projectile kept re-aiming at that fixed point, overshot it, flipped
	# direction every frame, and orbited there forever -- never reaching
	# max_range, never despawning (reported as "stuck" with the effect never
	# removed). Falling back to the last real direction lets it fly on through
	# and expire normally.
	if is_instance_valid(homing_target) and homing_target.is_in_group(target_group):
		direction = (homing_target.global_position - global_position).normalized()
		rotation = direction.angle()
	position += direction * speed * delta
	if global_position.distance_to(_spawn_position) >= max_range:
		_deactivate()


func _on_body_entered(body: Node) -> void:
	# _active guard matters even with monitoring=false: a body_entered signal
	# from this same physics frame can still be queued for emission after
	# _deactivate() has already flipped monitoring off.
	if not _active:
		return
	if not body.is_in_group(target_group) or not body.has_method("take_damage"):
		return
	if body in _already_hit:
		return
	_already_hit.append(body)
	body.take_damage(damage, _shot_element())
	if body.has_method("apply_status"):
		for roll in status_rolls:
			if randf() < roll["chance"]:
				body.apply_status(roll["element"], roll["duration"])
	if impact_flash_color.a > 0.0:
		# Visual-only pop on each enemy hit (every pierce), no damage of its own.
		ImpactVFX.flash_burst(body.global_position, impact_flash_radius, impact_flash_color, self)
	if burst_radius > 0.0:
		_apply_burst(body)
	if chain_count > 0:
		_apply_chain(body)
	_hits_remaining -= 1
	if _hits_remaining <= 0:
		_deactivate()


func _apply_burst(origin_body: Node) -> void:
	# Explosive Volley / Frozen Burst / Ice Wall Nova: guaranteed splash (not a
	# chance roll) to every enemy within radius of the primary hit.
	if not is_instance_valid(origin_body):
		return
	var element: String = status_rolls[0]["element"] if not status_rolls.is_empty() else ""
	if burst_vfx_id == "ice_burst":
		ImpactVFX.ice_burst(origin_body.global_position, burst_radius, self)
	elif burst_vfx_id == "ice_wall_nova":
		ImpactVFX.ice_wall_nova_burst(origin_body.global_position, burst_radius, self)
	elif element == StatusEffects.FIRE:
		ImpactVFX.fire_explosion(origin_body.global_position, burst_radius, self)
	else:
		ImpactVFX.flash_burst(origin_body.global_position, burst_radius, _burst_color_for(element), self)
		if element == StatusEffects.FROST:
			ImpactVFX.ice_shards(origin_body.global_position, self)
	for enemy in origin_body.get_tree().get_nodes_in_group(target_group):
		if enemy == origin_body or not is_instance_valid(enemy) or enemy in _already_hit:
			continue
		if not enemy.has_method("take_damage"):
			continue
		if origin_body.global_position.distance_to(enemy.global_position) > burst_radius:
			continue
		_already_hit.append(enemy)
		enemy.take_damage(damage, _shot_element())
		if enemy.has_method("apply_status"):
			for roll in status_rolls:
				if randf() < roll["chance"]:
					enemy.apply_status(roll["element"], roll["duration"])


func _apply_chain(from_body: Node) -> void:
	# Chain Spark: jumps to chain_count additional nearest distinct enemies in
	# sequence, each within CHAIN_RANGE of the previous hit.
	var last := from_body
	for _i in chain_count:
		var next := _find_chain_target(last)
		if next == null:
			return
		_already_hit.append(next)
		ImpactVFX.chain_bolt(last.global_position, next.global_position, Color(0.75, 0.4, 1.0, 0.9), self)
		ImpactVFX.spark_burst(next.global_position, ImpactVFX.CHAIN_SPARK_BURST_RADIUS, self)
		next.take_damage(damage, _shot_element())
		if next.has_method("apply_status"):
			for roll in status_rolls:
				if randf() < roll["chance"]:
					next.apply_status(roll["element"], roll["duration"])
		last = next


func _shot_element() -> String:
	# The element this shot carries, for BossBase's affinity resist/weak math.
	# "" for the basic line (no status rolls) = untyped physical damage.
	return status_rolls[0]["element"] if not status_rolls.is_empty() else ""


func _burst_color_for(element: String) -> Color:
	match element:
		StatusEffects.FIRE:
			return Color(1.0, 0.45, 0.1, 0.85)
		StatusEffects.FROST:
			return Color(0.6, 0.9, 1.0, 0.85)
		StatusEffects.LIGHTNING:
			return Color(0.7, 0.3, 1.0, 0.85)
	return Color(1.0, 0.85, 0.4, 0.85)


func _find_chain_target(from_body: Node) -> Node:
	if not is_instance_valid(from_body):
		return null
	var best: Node = null
	var best_dist := CHAIN_RANGE
	for enemy in from_body.get_tree().get_nodes_in_group(target_group):
		if not is_instance_valid(enemy) or enemy in _already_hit or enemy == from_body:
			continue
		if not enemy.has_method("take_damage"):
			continue
		var d: float = from_body.global_position.distance_to(enemy.global_position)
		if d <= best_dist:
			best = enemy
			best_dist = d
	return best


func _deactivate() -> void:
	_active = false
	visible = false
	set_physics_process(false)
	# _deactivate() runs synchronously inside _on_body_entered() (a body_entered
	# signal callback) on every confirmed hit -- Godot rejects a direct
	# `monitoring = false` from inside that callback ("Function blocked during
	# in/out signal"), throwing a real engine error on every single hit in the
	# game. Must go through set_deferred() instead.
	set_deferred("monitoring", false)
	var pool := get_tree().get_first_node_in_group("projectile_pool")
	if is_instance_valid(pool):
		pool.release(self)
	else:
		queue_free()
