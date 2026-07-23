extends RefCounted
class_name ElementFusions

# (2026-07-22) Late-game elemental fusions -- the reward for a deep run that
# fully maxes TWO element lines. Maxing both lines of a pair permanently makes
# the player's attacks carry BOTH of that pair's statuses, so the pair's
# on-enemy combo (see StatusEffects._evaluate_combos) fires reliably instead of
# only on the rare occasion an enemy happened to catch both statuses at once
# (hard, since only one element auto-fires at a time). Data-only here; unlock
# tracking lives on Player (active_fusions + _maybe_unlock_fusions), the apply
# mechanic in StatusEffects.apply(), and the combo damage in
# StatusEffects._evaluate_combos().
#
# pair_id is the two element status-names sorted and joined, so a lookup is
# order-independent ("fire_frost" whether you maxed fire or frost first). The
# three keys below are exactly what pair_id() produces for the three pairs,
# since "fire" < "frost" < "lightning" alphabetically.

const FIRE := "fire"
const FROST := "frost"
const LIGHTNING := "lightning"

const FUSIONS := {
	"fire_frost": {
		"name": "Frostfire",
		"elements": [FIRE, FROST],
		"icon": "res://art/ui/icons/icon_frozen_burst.png",
		"description": "Attacks chill and burn at once — afflicted enemies detonate in a frost-fire blast.",
	},
	"frost_lightning": {
		"name": "Superconductor",
		"elements": [FROST, LIGHTNING],
		"icon": "res://art/ui/icons/icon_chain_spark.png",
		"description": "Attacks chill and shock at once — afflicted enemies discharge, arcing damage to nearby foes.",
	},
	"fire_lightning": {
		"name": "Overload",
		"elements": [FIRE, LIGHTNING],
		"icon": "res://art/ui/icons/icon_storm_overload.png",
		"description": "Attacks burn and shock at once — afflicted enemies overload in a wide explosive discharge.",
	},
}

# Fusion-identity tint, distinct from the per-element label colours -- fusions
# read as their own "combined" line in the HUD and pause menu.
const FUSION_COLOR := Color(1.0, 0.72, 0.95, 1.0)


static func display_name(pair: String) -> String:
	return FUSIONS[pair]["name"] if FUSIONS.has(pair) else ""


static func description(pair: String) -> String:
	return FUSIONS[pair]["description"] if FUSIONS.has(pair) else ""


static func icon_path(pair: String) -> String:
	return FUSIONS[pair]["icon"] if FUSIONS.has(pair) else ""


static func pair_id(a: String, b: String) -> String:
	var arr := [a, b]
	arr.sort()
	return "%s_%s" % [arr[0], arr[1]]


static func partner(pair: String, element: String) -> String:
	# The OTHER element in `pair` given one of its two elements, or "" if
	# `element` isn't part of `pair`.
	if not FUSIONS.has(pair):
		return ""
	var els: Array = FUSIONS[pair]["elements"]
	if element == els[0]:
		return els[1]
	if element == els[1]:
		return els[0]
	return ""
