extends Resource
class_name SkillData

@export var id: String
@export var display_name: String
@export var base_damage: float = 5.0
@export var cooldown: float = 0.8
@export var mana_cost: float = 0.0  # 0 for Basic Shot (auto-fire, no mana gate)
@export var projectile_scene: PackedScene
@export var pierce_count: int = 0  # forwarded to Projectile; 0 = single-hit-then-free
@export var projectile_count: int = 1  # simultaneous projectiles per shot
