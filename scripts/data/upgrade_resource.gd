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
@export var tier: int = 1  # 0 = repeatable (see fire_damage_boost.tres etc.), 1 = root unlock, 2/3 = branch tiers
@export var exclusive_group: String = ""  # e.g. "fire_t2" -- picking either node in the group locks out its sibling; empty for tier-1 roots
