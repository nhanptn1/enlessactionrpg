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
