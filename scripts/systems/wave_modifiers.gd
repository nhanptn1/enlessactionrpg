extends RefCounted
class_name WaveModifiers
## Per-wave composition events. One may be rolled for each generated wave from
## WaveManager.WAVE_MODIFIER_START_WAVE onward.
##
## (2026-07-24) The sibling of RunModifiers, and deliberately NOT the same
## system: a run modifier is rolled once and lasts the whole run, which is a
## flavour of that run. These are rolled per wave, which is variety WITHIN a
## run -- the thing the scaling ceilings took away. Measured before building:
## monster count caps at wave 11, max concurrent at 12, spawn interval at 20,
## speed at 38, HP at 49, and enemy damage never scaled at all, so from wave 49
## every regular wave was numerically identical forever (entry 94). Elite
## density fixed the slope through wave 32; this is what keeps wave 80
## different from wave 50.
##
## The point is that these change what a wave IS -- which species, how they
## arrive -- rather than nudging a multiplier that was capped for a reason.
##
## Keys, all optional (a modifier only declares what defines it):
##   species          -- "flying" | "tank": restrict the wave to those species
##   count_mult       -- monsters in the wave
##   hp_mult          -- on top of the wave's own HP scaling
##   speed_mult       -- on top of the wave's own speed scaling (see BLITZ note)
##   max_active_add   -- concurrent monsters on screen
##   spawn_interval_mult -- lower = they arrive faster
##   elite_chance_mult   -- multiplies the wave's elite rate

const MODIFIERS := {
	"skyfall": {
		"display_name": "Skyfall",
		"description": "Nothing but fliers.",
		# No numeric changes at all -- the composition IS the modifier. Fliers
		# dive and zigzag rather than walking straight down, so this is a
		# different tracking problem, not a harder version of the same one.
		"species": "flying",
	},
	"vanguard": {
		"display_name": "Vanguard",
		"description": "Armoured only. Fewer, far tougher.",
		# Fewer but meaner: a slow grind where the lose line does the talking,
		# and the wave where failing to focus fire actually costs you.
		"species": "tank",
		"count_mult": 0.55,
		"hp_mult": 1.35,
	},
	"swarm": {
		"display_name": "Swarm",
		"description": "They come thick and fast, but frail.",
		# The inverse of Vanguard: a rush instead of a queue. HP drops well
		# below baseline so it reads as pressure to clear, not a wall.
		"count_mult": 1.25,
		"hp_mult": 0.6,
		"max_active_add": 6,
		"spawn_interval_mult": 0.55,
	},
	"elite_guard": {
		"display_name": "Elite Guard",
		"description": "Elites everywhere.",
		"elite_chance_mult": 2.0,
	},
	"blitz": {
		"display_name": "Blitz",
		"description": "Everything moves much faster.",
		# The only thing in the game allowed past SPEED_MULT_CEILING, and only
		# for one wave. That ceiling exists so a slow keeps meaning something
		# forever (entry 80) -- punching through it permanently is what broke
		# shock at high waves in the first place. For a single wave it's the
		# intended spike, and the absolute controls (Frost freeze, the opening
		# of a shock) still stop these enemies dead, because those set velocity
		# to zero rather than scaling it. WaveManager clamps the result to
		# BLITZ_SPEED_CEILING so this can't compound without bound either.
		"speed_mult": 1.45,
	},
}


static func has(modifier_id: String) -> bool:
	return MODIFIERS.has(modifier_id)


static func ids() -> Array:
	return MODIFIERS.keys()


static func get_value(modifier_id: String, key: String, default: float = 1.0) -> float:
	if not MODIFIERS.has(modifier_id):
		return default
	return MODIFIERS[modifier_id].get(key, default)


static func species_filter(modifier_id: String) -> String:
	if not MODIFIERS.has(modifier_id):
		return ""
	return MODIFIERS[modifier_id].get("species", "")


static func display_name(modifier_id: String) -> String:
	if not MODIFIERS.has(modifier_id):
		return ""
	return MODIFIERS[modifier_id]["display_name"]


static func description(modifier_id: String) -> String:
	if not MODIFIERS.has(modifier_id):
		return ""
	return MODIFIERS[modifier_id]["description"]
