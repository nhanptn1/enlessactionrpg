extends RefCounted
class_name CharacterClasses

# (2026-07-21) Phase 4, final pillar: character classes -- the last sub-option
# from the run-variety plan doc (entry 53 chose random modifiers first and
# deferred this). A class is a CHOSEN identity picked at run start (vs. run
# modifiers, which are rolled); the two stack multiplicatively. Same
# static-const-dict convention as RunModifiers.MODIFIERS/BossBase.MUTATIONS.
#
# First cut is deliberately stat-identity only over the same 4 skill lines --
# no class-exclusive skills, so every existing icon/tree/upgrade keeps
# working unchanged. Visuals are a class-colored tint on the shared archer
# art (the elite/mutation/affinity technique), per direct user choice --
# real per-class sprite sheets can drop in later as a pure art pass.
#
# Missing keys mean "no change" (see get_value()); Ranger is the explicit
# no-tradeoff baseline so a player who ignores the system entirely loses
# nothing by mashing the first button.
const CLASSES := {
	"ranger": {
		"display_name": "Ranger",
		"description": "The classic archer. Balanced, no tradeoffs.",
		"color": Color(1.0, 1.0, 1.0, 1.0),
		"vfx_color": Color(0.5, 1.0, 0.55, 0.95),  # bright green -- class-skill impact/telegraph highlight
		"skills": ["res://resources/skills/class_twin_volley.tres"],
	},
	"sniper": {
		"display_name": "Sniper",
		"description": "+15% crit chance, +15% projectile speed, -15% max HP.",
		"color": Color(1.15, 1.05, 0.7, 1.0),
		"crit_chance_bonus": 0.15,
		"projectile_speed_mult": 1.15,
		"max_hp_mult": 0.85,
		"vfx_color": Color(1.0, 0.9, 0.3, 0.95),  # bright gold
		"skills": ["res://resources/skills/class_power_shot.tres"],
	},
	"elementalist": {
		"display_name": "Elementalist",
		"description": "+25% elemental skill damage, -15% physical damage.",
		"color": Color(1.05, 0.85, 1.2, 1.0),
		"elemental_dmg_mult": 1.25,
		"physical_dmg_mult": 0.85,
		"vfx_color": Color(0.85, 0.45, 1.0, 0.95),  # bright violet
		"skills": ["res://resources/skills/class_arcane_bolt.tres"],
	},
	"juggernaut": {
		"display_name": "Juggernaut",
		"description": "+40% max HP, -15% physical damage.",
		"color": Color(0.85, 1.0, 1.15, 1.0),
		"max_hp_mult": 1.4,
		"physical_dmg_mult": 0.85,
		"vfx_color": Color(0.5, 0.9, 1.0, 0.95),  # bright cyan
		"skills": ["res://resources/skills/class_shockwave.tres"],
	},
	# (2026-07-24) Traps moved off the physical line and became this class, per
	# user. The physical line is now about arrows -- more of them, hitting more
	# things -- and a trap chain sat oddly inside that: it ignores arrow count
	# entirely, so every arrow-growth pick went dead the moment you took it.
	# As a class it keeps all four original trap steps' behaviour (the third
	# card folds the old Volatile Trap and Trap Mastery detonation into one)
	# and becomes something you commit to at run start instead of drifting into.
	# Slower attacks, harder hits: traps are placed, not sprayed.
	"trapper": {
		"display_name": "Trapper",
		"description": "+25% physical damage, -15% attack speed.",
		"color": Color(1.05, 0.9, 0.6, 1.0),
		"physical_dmg_mult": 1.25,
		"cooldown_mult": 1.15,
		"vfx_color": Color(1.0, 0.78, 0.35, 0.95),  # amber -- matches the trap zone's own glow
		"skills": ["res://resources/skills/class_snare_trap.tres"],
	},
}
# (2026-07-24) Each class now has ONE active skill, not a 3-tier chain that
# swapped it wholesale -- per user, growth comes from repeatable pickup cards
# (class_damage_boost / class_cooldown_boost) instead of new skills. Kept as an
# ARRAY so the tier machinery every other line uses still applies unchanged.
# Loaded lazily in apply_element_upgrade()'s CLASS branch -- only the picked
# class's skill ever loads in a given run.


static func get_value(class_id: String, key: String, default_value: float = 1.0) -> float:
	return CLASSES.get(class_id, {}).get(key, default_value)


static func get_color(class_id: String) -> Color:
	return CLASSES.get(class_id, {}).get("color", Color.WHITE)


static func get_vfx_color(class_id: String) -> Color:
	# Bright, saturated highlight color for the class skill line's in-game
	# effects (impact flashes, telegraphs, pulses) -- distinct from the near-
	# white sprite-tint `color` above.
	return CLASSES.get(class_id, {}).get("vfx_color", Color(1.0, 0.95, 0.6, 0.95))
