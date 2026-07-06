extends CharacterBody2D
class_name EnemyBase

const CONTACT_DAMAGE_INTERVAL := 0.6

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hurtbox: Area2D = $Hurtbox
@onready var contact_timer: Timer = $ContactDamageTimer
@onready var screen_check: VisibleOnScreenNotifier2D = $ScreenCheck
@onready var attack_timer: Timer = $AttackTimer

var data: EnemyData
var current_hp: float
var _player_in_contact: Node2D = null
var _hp_mult := 1.0
var _speed_mult := 1.0
var _damage_mult := 1.0
var _xp_override := -1  # -1 sentinel = "use data.xp_reward unmodified"
var _time_alive := 0.0


func setup(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1) -> void:
	data = enemy_data  # caller MUST call this before add_child()
	_hp_mult = hp_mult
	_speed_mult = speed_mult
	_damage_mult = damage_mult
	_xp_override = xp_override


func _ready() -> void:
	add_to_group("enemy")
	current_hp = data.base_hp * _hp_mult
	if data.movement_pattern == "dive":
		var player := get_tree().get_first_node_in_group("player")
		if is_instance_valid(player):
			velocity = (player.global_position - global_position).normalized() * data.base_speed * _speed_mult
		else:
			velocity = Vector2(0, data.base_speed * _speed_mult)
	else:
		velocity = Vector2(0, data.base_speed * _speed_mult)
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	contact_timer.wait_time = CONTACT_DAMAGE_INTERVAL
	contact_timer.timeout.connect(_on_contact_timer_timeout)
	screen_check.screen_exited.connect(queue_free)
	sprite.play("move")
	if data.attack_type == "ranged":
		attack_timer.wait_time = data.attack_interval
		attack_timer.timeout.connect(_on_attack_timer_timeout)
		attack_timer.start()


func _physics_process(delta: float) -> void:
	_time_alive += delta
	if data.movement_pattern == "zigzag":
		velocity.x = sin(_time_alive * data.zigzag_frequency * TAU) * data.zigzag_speed
	move_and_slide()


func take_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0.0:
		_die()


func _on_hurtbox_body_entered(body: Node) -> void:
	if data.attack_type != "contact":
		return
	if body.is_in_group("player") and body.has_method("take_damage"):
		_player_in_contact = body
		body.take_damage(data.base_damage * _damage_mult)
		contact_timer.start()


func _on_hurtbox_body_exited(body: Node) -> void:
	if body == _player_in_contact:
		_player_in_contact = null
		contact_timer.stop()


func _on_contact_timer_timeout() -> void:
	if is_instance_valid(_player_in_contact):
		_player_in_contact.take_damage(data.base_damage * _damage_mult)


func _on_attack_timer_timeout() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or data.projectile_scene == null:
		return
	var proj = data.projectile_scene.instantiate()
	proj.direction = (player.global_position - global_position).normalized()
	proj.damage = data.base_damage * _damage_mult
	proj.speed = data.projectile_speed
	proj.target_group = "player"
	proj.global_position = global_position
	get_tree().current_scene.add_child(proj)


func _die() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("gain_xp"):
		var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
		player.gain_xp(xp_reward)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm):
		wm.notify_enemy_died()
	queue_free()
