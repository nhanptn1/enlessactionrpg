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
	"fire_frost": {"name": "Frostfire", "elements": [FIRE, FROST]},
	"frost_lightning": {"name": "Superconductor", "elements": [FROST, LIGHTNING]},
	"fire_lightning": {"name": "Overload", "elements": [FIRE, LIGHTNING]},
}


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
