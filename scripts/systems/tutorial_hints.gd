extends RefCounted
class_name TutorialHints

# (2026-07-21) Onboarding: lightweight contextual hints, each shown once ever
# (tracked in SaveManager.seen_hints) the first time its mechanic becomes
# relevant. No upfront tutorial wall -- the game teaches itself as systems
# unlock. HUD owns the trigger hooks + the on-screen banner; this is just the
# copy, kept as data so wording is one place to tune.
const HINTS := {
	"move": "Drag anywhere (or A/D) to move.\nYou fire automatically at the nearest enemy.",
	"dash": "Tap DASH (or Space) to dash.\nYou're invincible mid-dash -- use it to dodge!",
	"switch_element": "You have a second element!\nTap an element row (top-left) to switch your active attack.",
	"boss": "BOSS incoming!\nWatch for glowing telegraph circles and dash out of them.",
	"affinity": "This boss RESISTS an element.\nCheck the cycle (top-right) and switch to the green one.",
	"ultimate": "ULTIMATE charged!\nPress Q (or tap the gold icon) to unleash it.",
}
