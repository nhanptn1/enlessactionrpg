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
@export var movement_behavior: MovementBehavior  # e.g. res://resources/behaviors/zigzag_movement.tres
@export var attack_behavior: AttackBehavior      # e.g. res://resources/behaviors/ranged_attack.tres
@export var zigzag_speed: float = 0.0     # px/sec, max horizontal speed -- read by ZigzagMovement
@export var zigzag_frequency: float = 1.2 # oscillations per second -- read by ZigzagMovement
@export var cluster_size: int = 1         # bodies spawned per queue entry
@export var projectile_scene: PackedScene # read by RangedAttack
@export var attack_interval: float = 2.0  # ranged attack cooldown, seconds -- read by RangedAttack
@export var projectile_speed: float = 220.0
@export var drop_chance: float = 0.0      # chance to drop an item on death
# "basic" | "fast" | "swarm" | "tank" -- read by WaveManager._generate_wave()
# to keep procedural waves 6+ from rolling multiple high-HP tank species at
# once (plan/monster-waves-progression.txt's "10% tank" mix rule). Only
# matters for entries in WaveManager.procedural_enemy_pool; irrelevant for
# hand-authored waves, bosses, or minions.
@export var role: String = "basic"
