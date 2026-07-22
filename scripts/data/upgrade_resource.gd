extends Resource
class_name UpgradeResource

# CLASS (2026-07-21): class-skill-tree upgrades -- gated per character class
# via required_class below, tiers 1-3, applied through the same wave-clear
# picker as everything else. See CharacterClasses.CLASSES and
# player.gd::apply_element_upgrade()'s CLASS branch.
enum ElementType { FIRE, FROST, LIGHTNING, PHYSICAL, CLASS }

@export var id: String
@export var element: ElementType = ElementType.FIRE
@export var title: String
@export_multiline var description: String
@export var icon: Texture2D
@export var stat_to_modify: String  # must match a Player var name (e.g. "fire_spread_chance")
@export var modification_value: float = 0.20
@export var tier: int = 1  # 0 = repeatable (see fire_damage_boost.tres etc.), 1 = root unlock, 2/3/4 = tier upgrades
@export var max_stacks: int = 0  # 0 = uncapped; >0 caps how many times a repeatable (tier 0) card can be picked, so a path stops being offered once its skill tier AND every stat card are maxed
@export var exclusive_group: String = ""  # unused now that every tier is a single direct upgrade -- kept for schema stability, never non-empty going forward
@export var required_class: String = ""  # "" = any class; CLASS-element upgrades set this to their owning class id (see CharacterClasses.CLASSES)
