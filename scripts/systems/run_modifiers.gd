extends RefCounted
class_name RunModifiers
## Phase 3 pillar 3: run variety via random run modifiers. One is rolled per
## run (see player.gd::_apply_run_modifier(), called from _ready() right
## after _apply_meta_upgrades()) and stays active for the whole run -- no
## player choice for this first cut, matching the plan doc's own "random run
## modifiers" framing (not "run modifier selection"). Static-only, no state
## of its own, same convention as StatusEffects.
##
## Each modifier is a blessing+curse pair, applied once at spawn via the
## generic keys below. All keys are optional (missing = 1.0 for a *_mult key,
## 0.0 for a *_add key) -- a modifier only needs to set the 2 keys that
## actually define its pair, matching boss_base.gd's own MUTATIONS pattern.
## player_* keys are applied directly in player.gd; enemy_* keys are read by
## wave_manager.gd (see _get_modifier_mult()) since WaveManager owns that scaling.

const MODIFIERS := {
	"berserkers_bargain": {
		"display_name": "Berserker's Bargain",
		"description": "+30% damage, -30% max HP.",
		"player_damage_mult": 1.3,
		"player_max_hp_mult": 0.7,
	},
	"iron_skin": {
		"display_name": "Iron Skin",
		"description": "+40% max HP, -20% damage.",
		"player_max_hp_mult": 1.4,
		"player_damage_mult": 0.8,
	},
	"adrenaline_rush": {
		"display_name": "Adrenaline Rush",
		"description": "20% faster attacks, -15% max HP.",
		"player_cooldown_mult": 0.8,
		"player_max_hp_mult": 0.85,
	},
	"bounty_hunter": {
		"display_name": "Bounty Hunter",
		"description": "+50% XP gain, enemies have +25% HP.",
		"player_xp_gain_mult": 1.5,
		"enemy_hp_mult": 1.25,
	},
	"swarm_warning": {
		"display_name": "Swarm Warning",
		"description": "+30% monsters per wave, +20% XP gain.",
		"enemy_count_mult": 1.3,
		"player_xp_gain_mult": 1.2,
	},
}


static func roll_random_id() -> String:
	var ids := MODIFIERS.keys()
	return ids[randi() % ids.size()]


static func get_mult(modifier_id: String, key: String, default: float = 1.0) -> float:
	return MODIFIERS.get(modifier_id, {}).get(key, default)
