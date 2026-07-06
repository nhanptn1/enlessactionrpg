extends CharacterBody2D
class_name EnemyBase

const CONTACT_DAMAGE_INTERVAL := 0.6

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hurtbox: Area2D = $Hurtbox
@onready var contact_timer: Timer = $ContactDamageTimer
@onready var screen_check: VisibleOnScreenNotifier2D = $ScreenCheck

var data: EnemyData
var current_hp: float
var _player_in_contact: Node2D = null
var _hp_mult := 1.0
var _speed_mult := 1.0
var _damage_mult := 1.0
var _xp_override := -1  # -1 sentinel = "use data.xp_reward unmodified"


func setup(enemy_data: EnemyData, hp_mult: float = 1.0, speed_mult: float = 1.0, damage_mult: float = 1.0, xp_override: int = -1) -> void:
	data = enemy_data  # caller MUST call this before add_child()
	_hp_mult = hp_mult
	_speed_mult = speed_mult
	_damage_mult = damage_mult
	_xp_override = xp_override


func _ready() -> void:
	add_to_group("enemy")
	current_hp = data.base_hp * _hp_mult
	velocity = Vector2(0, data.base_speed * _speed_mult)
	hurtbox.body_entered.connect(_on_hurtbox_body_entered)
	hurtbox.body_exited.connect(_on_hurtbox_body_exited)
	contact_timer.wait_time = CONTACT_DAMAGE_INTERVAL
	contact_timer.timeout.connect(_on_contact_timer_timeout)
	screen_check.screen_exited.connect(queue_free)
	sprite.play("move")


func _physics_process(_delta: float) -> void:
	move_and_slide()


func take_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0.0:
		_die()


func _on_hurtbox_body_entered(body: Node) -> void:
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


func _die() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("gain_xp"):
		var xp_reward: int = _xp_override if _xp_override >= 0 else data.xp_reward
		player.gain_xp(xp_reward)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm):
		wm.notify_enemy_died()
	queue_free()
