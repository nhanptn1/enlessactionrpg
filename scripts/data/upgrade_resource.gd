extends Resource
class_name UpgradeResource

enum ElementType { FIRE, FROST, LIGHTNING, PHYSICAL }

@export var id: String
@export var element: ElementType = ElementType.FIRE
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
@export var stat_to_modify: String  # must match a Player var name (e.g. "fire_spread_chance")
@export var modification_value: float = 0.20
@export var tier: int = 1  # 0 = repeatable (see fire_damage_boost.tres etc.), 1 = root unlock, 2/3/4 = tier upgrades
@export var exclusive_group: String = ""  # unused now that every tier is a single direct upgrade -- kept for schema stability, never non-empty going forward
