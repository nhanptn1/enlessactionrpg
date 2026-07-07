extends Resource
class_name ItemData

@export var id: String
@export var display_name: String
@export var category: String            # "weapon" | "armor" | "accessory" | "consumable"
@export var rarity: String = "common"    # "common" | "rare" | "epic"
@export var icon: Texture2D
@export var effect_type: String = "stat_boost"  # "stat_boost" | "instant_heal" | "instant_bomb" | "instant_xp"
@export var upgrade_id: String = ""      # only for stat_boost — must match a value in Player.UPGRADE_POOL
@export var upgrade_stacks: int = 1      # calls apply_upgrade this many times (rarity scaling)
@export var effect_amount: float = 0.0   # only for instant_heal/instant_bomb/instant_xp
