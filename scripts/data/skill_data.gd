extends Resource
class_name SkillData

enum FireMode { PROJECTILE, ARROW_RAIN, TRAP_SHOT }

@export var id: String
@export var display_name: String
@export var base_damage: float = 5.0
@export var cooldown: float = 0.8
@export var mana_cost: float = 0.0
@export var projectile_scene: PackedScene
@export var pierce_count: int = 0
@export var projectile_count: int = 1
@export var fire_mode: FireMode = FireMode.PROJECTILE
@export var rain_arrow_count: int = 10
@export var rain_spread_width: float = 600.0
@export var trap_duration: float = 3.0
@export var trap_radius: float = 55.0
@export var trap_scene: PackedScene
