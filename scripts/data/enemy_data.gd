extends Resource
class_name EnemyData

@export var id: String
@export var display_name: String
@export var scene: PackedScene
@export var base_hp: float = 10.0
@export var base_speed: float = 80.0
@export var base_damage: float = 5.0
@export var xp_reward: int = 5
@export var tier: int = 1
@export var attack_type: String = "contact"  # "contact" | "pattern" (bosses, MVP+)
@export var movement_pattern: String = "straight"  # "straight" | "zigzag" | "dive"
@export var zigzag_speed: float = 0.0     # px/sec, max horizontal speed
@export var zigzag_frequency: float = 1.2 # oscillations per second
@export var cluster_size: int = 1         # bodies spawned per queue entry
@export var projectile_scene: PackedScene # only used when attack_type == "ranged"
@export var attack_interval: float = 2.0  # ranged attack cooldown, seconds
@export var projectile_speed: float = 220.0
