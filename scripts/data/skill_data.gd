extends Resource
class_name SkillData

enum FireMode { PROJECTILE, ARROW_RAIN, TRAP_SHOT }

@export var id: String
@export var display_name: String
@export var icon: Texture2D
@export var base_damage: float = 5.0
@export var cooldown: float = 0.8
@export var projectile_scene: PackedScene
@export var pierce_count: int = 0
@export var projectile_count: int = 1
@export var fire_mode: FireMode = FireMode.PROJECTILE
@export var rain_arrow_count: int = 10  # ARROW_RAIN: number of telegraphed impact zones (not a literal arrow count)
@export var rain_spread_width: float = 600.0  # ARROW_RAIN: scatter radius of each zone around its anchor enemy
@export var telegraph_time: float = 0.7  # ARROW_RAIN: warning-circle duration before impact lands
@export var trap_duration: float = 3.0
@export var trap_radius: float = 55.0  # also reused by ARROW_RAIN as each impact zone's hit radius
@export var trap_scene: PackedScene
@export var burst_radius: float = 0.0  # 0 = off; on hit, splash damage+status to enemies within this radius (Frozen Burst, Ice Wall Nova, Explosive Volley)
@export var chain_count: int = 0  # 0 = off; on hit, chain to N additional nearest distinct enemies in sequence (Chain Spark)
@export var visual_scale: float = 1.0  # multiplies the projectile's Visual node scale (bigger arrow for Explosive Volley)
@export var burst_vfx_id: String = ""  # "" = element-default burst look; set to pick a dedicated ImpactVFX burst animation (e.g. "ice_burst", "ice_wall_nova") when a skill needs its own art instead of sharing its element's default
