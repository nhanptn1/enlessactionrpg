extends Resource
class_name WaveData

@export var wave_number: int = 1
@export var enemy_pool: Array[EnemyData] = []
@export var spawn_counts: Array[int] = []  # parallel array to enemy_pool
@export var spawn_interval: float = 1.0
@export var is_boss_wave: bool = false
@export var max_active: int = 15  # cap on concurrently alive regular monsters -- see WaveManager._on_spawn_tick()
