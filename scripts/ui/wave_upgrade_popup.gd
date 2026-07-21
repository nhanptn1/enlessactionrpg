extends CanvasLayer
class_name WaveUpgradePopup

# Ornate per-element card frames (art/ui/card_frame_*.png, cropped from a
# supplied reference sheet) applied as each button's background via
# StyleBoxTexture -- built once in _ready() and reused, not recreated per card.
const CARD_FRAME_PATHS := {
	UpgradeResource.ElementType.FIRE: "res://art/ui/card_frame_fire.png",
	UpgradeResource.ElementType.FROST: "res://art/ui/card_frame_frost.png",
	UpgradeResource.ElementType.LIGHTNING: "res://art/ui/card_frame_lightning.png",
	# Recolored from card_frame_fire.png (hue-rotated warm red/orange -> green,
	# same ornate frame shape reused) rather than a fresh reference-sheet
	# extraction -- green was open hue space (Fire=red/orange, Frost=blue,
	# Lightning=purple/gold) and fits the archer's forest-ranger theme.
	UpgradeResource.ElementType.PHYSICAL: "res://art/ui/card_frame_physical.png",
	# Class-skill cards reuse the physical frame -- class skills are untyped/
	# physical damage, and a 5th bespoke frame recolor isn't worth it yet.
	UpgradeResource.ElementType.CLASS: "res://art/ui/card_frame_physical.png",
}
const CARD_TEXTURE_MARGIN := 40.0  # 9-slice margin so corner flourishes don't stretch when the button isn't the source's exact size

@export var upgrade_pool: Array[UpgradeResource] = []

@onready var panel: Control = $Panel
@onready var choice_buttons: Array[Button] = [$Panel/VBox/HBox/Choice1, $Panel/VBox/HBox/Choice2, $Panel/VBox/HBox/Choice3]
@onready var choice_icons: Array[SkillIcon] = [$Panel/VBox/HBox/Choice1/Icon, $Panel/VBox/HBox/Choice2/Icon, $Panel/VBox/HBox/Choice3/Icon]
@onready var choice_labels: Array[Label] = [$Panel/VBox/HBox/Choice1/TitleLabel, $Panel/VBox/HBox/Choice2/TitleLabel, $Panel/VBox/HBox/Choice3/TitleLabel]

var player: Node
var _pending_choices: Array[UpgradeResource] = []
var _card_styles: Dictionary = {}  # UpgradeResource.ElementType -> StyleBoxTexture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("wave_upgrade_popup")  # lets SkillTreeView read upgrade_pool without a direct node reference
	panel.visible = false
	player = get_tree().get_first_node_in_group("player")
	SignalBus.wave_cleared.connect(_on_wave_cleared)
	for i in 3:
		choice_buttons[i].pressed.connect(_on_choice_selected.bind(i))
	for element in CARD_FRAME_PATHS:
		var stylebox := StyleBoxTexture.new()
		stylebox.texture = load(CARD_FRAME_PATHS[element])
		stylebox.texture_margin_left = CARD_TEXTURE_MARGIN
		stylebox.texture_margin_right = CARD_TEXTURE_MARGIN
		stylebox.texture_margin_top = CARD_TEXTURE_MARGIN
		stylebox.texture_margin_bottom = CARD_TEXTURE_MARGIN
		_card_styles[element] = stylebox


func _on_wave_cleared(_wave_number: int, _was_boss: bool) -> void:
	if not is_instance_valid(player):
		return
	# Each element offers its next tier's node(s) as a unit -- a tier-2/3 fork
	# is 2 mutually exclusive options, and both are shown together so picking
	# one is a real, visible choice rather than randomly seeing only one side
	# of the fork some waves and the other side on a later wave. Elements are
	# processed in random order and an element's node(s) are only added if
	# they entirely fit in the remaining slots, so a fork (2 slots) never gets
	# split across waves -- at most one fork can appear alongside one other
	# element's single node in the 3 available slots. PHYSICAL (Multishot ->
	# Piercing Arrow -> Trap Shot -> Rigged Trap -> Volatile Trap -> Trap
	# Mastery, 6 tiers) competes for the same 3 slots as the elements -- it's
	# a linear chain with no forks, so its "unit" is always exactly 1 card.
	# It still has no per-skill icon art, so its cards fall back to SkillIcon's
	# procedural glyph (see skill_icon.gd).
	var element_order: Array = [UpgradeResource.ElementType.FIRE, UpgradeResource.ElementType.FROST, UpgradeResource.ElementType.LIGHTNING, UpgradeResource.ElementType.PHYSICAL, UpgradeResource.ElementType.CLASS]
	element_order.shuffle()
	_pending_choices.clear()
	for element in element_order:
		var candidates := _get_offerable_upgrades(element)
		if candidates.is_empty():
			continue
		if _pending_choices.size() + candidates.size() > 3:
			continue
		_pending_choices.append_array(candidates)
	if _pending_choices.is_empty():
		return  # every element already fully maxed -- nothing to offer this wave
	for i in 3:
		if i < _pending_choices.size():
			var upgrade: UpgradeResource = _pending_choices[i]
			choice_labels[i].text = upgrade.title
			choice_buttons[i].tooltip_text = upgrade.description
			_apply_card_style(choice_buttons[i], upgrade.element)
			choice_icons[i].texture = upgrade.icon
			choice_icons[i].element = upgrade.element
			choice_icons[i].queue_redraw()
			choice_buttons[i].visible = true
		else:
			choice_buttons[i].visible = false
	panel.visible = true
	GameManager.request_pause("wave_upgrade")


func _apply_card_style(button: Button, element: UpgradeResource.ElementType) -> void:
	var stylebox: StyleBoxTexture = _card_styles.get(element)
	if stylebox == null:
		return
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, stylebox)


func _get_offerable_upgrades(target_element: UpgradeResource.ElementType) -> Array[UpgradeResource]:
	# Returns exactly one offerable "unit" for this element, chosen at random
	# from whichever units currently exist: the next tier's single direct
	# upgrade (2026-07-16: no more forks -- every tier is exactly 1 resource
	# now) while the tree isn't maxed, plus -- once the element is unlocked
	# (tier >= 1) -- its repeatable tier=0 cards (damage/cooldown, plus a
	# 3rd flavor card per element -- duration for Fire, combo bonus for
	# Frost/Lightning), each its own single-resource unit. Picking one unit
	# (not all of them) keeps this element contributing at most one offer per
	# wave, same as before the repeatable cards existed.
	var current_tier := _current_level_for(target_element)
	var max_tier := _max_tier_for(target_element)
	var next_tier := current_tier + 1
	var tier_up: Array[UpgradeResource] = []
	if next_tier <= max_tier:
		for upgrade in upgrade_pool:
			if upgrade.element != target_element or upgrade.tier != next_tier:
				continue
			# CLASS-element cards are per-class exclusives -- only the card
			# matching the player's own picked class is ever offerable.
			if upgrade.element == UpgradeResource.ElementType.CLASS and upgrade.required_class != player.active_class_id:
				continue
			tier_up.append(upgrade)
	# (2026-07-17) Deliberately NOT gated on current_tier < max_tier -- an
	# earlier pass cut these off once an element hit max_tier, on the mistaken
	# assumption they'd become "a genuinely dead choice with nothing left to
	# scale into" (true for the level-up popup's own separate "+1 Arrow while
	# Trap Shot is active" case, since projectile_count truly has zero effect
	# there -- but NOT true here). fire_skill_dmg_mult/_cd_mult/etc. are read
	# by _fire_elemental_skill() on every single cast regardless of tier, so
	# they stay just as meaningful against tier-4's Wildfire Storm/Eternal
	# Frost/Storm Overload as they were at tier 1 -- a maxed element has no
	# more *tiers* to unlock, but its damage/cooldown/duration/combo power
	# still has real room to grow. Without this, a maxed element simply went
	# silent for the rest of the run once its tree was full.
	var repeatables: Array = []
	if current_tier >= 1:
		for upgrade in upgrade_pool:
			if upgrade.element == target_element and upgrade.tier == 0:
				var single: Array[UpgradeResource] = [upgrade]
				repeatables.append(single)
	if tier_up.is_empty() and repeatables.is_empty():
		return []
	if tier_up.is_empty():
		return repeatables[randi() % repeatables.size()]
	if repeatables.is_empty():
		return tier_up
	# (2026-07-21) A real tier-up used to be just one peer among N repeatable
	# flavors (3 per element today) in a flat random pick -- diluting its real
	# odds to 1/(1+3) = 25% any time this element got a slot at all, which
	# compounded across tiers 2->3->4->5 read as the tree being stuck for long
	# stretches (direct user report: "element path skills can't level up").
	# Tier-up now gets an even 50/50 against "any repeatable flavor" as a
	# whole, instead of losing ground the more flavors an element happens to
	# have.
	if randf() < 0.5:
		return tier_up
	return repeatables[randi() % repeatables.size()]


func _current_level_for(element: UpgradeResource.ElementType) -> int:
	match element:
		UpgradeResource.ElementType.FIRE:
			return player.fire_level
		UpgradeResource.ElementType.LIGHTNING:
			return player.lightning_level
		UpgradeResource.ElementType.FROST:
			return player.frost_level
		UpgradeResource.ElementType.PHYSICAL:
			return player.physical_level
		UpgradeResource.ElementType.CLASS:
			return player.class_skill_level
	return 0


func _max_tier_for(element: UpgradeResource.ElementType) -> int:
	# (2026-07-16) All 4 lines are a direct linear chain -- Physical was always
	# this shape (Multishot/Piercing Arrow/Arrow Rain/Trap Shot); Fire/Frost/
	# Lightning's former 2-option forks at tier 2/3/4 were merged into single
	# direct upgrades (see player.gd's apply_element_upgrade()). (2026-07-16)
	# Physical grew from 4 to 6 -- Trap Shot's former single-card "Trap Mastery"
	# capstone split into 3 progressive tiers (bare trap -> low explosion ->
	# bigger explosion -> max explosion) instead of one lump stat jump.
	# (2026-07-17) Fire/Frost/Lightning grew a 5th tier -- a one-time capstone
	# passive (Inferno Heart/Absolute Zero/Overcharge) on top of the 4-tier
	# active-skill chain, see player.gd's _update_elemental_skill() guard and
	# status_effects.gd's *_level >= 5 checks. Physical has no equivalent --
	# its own repeatable growth already comes from the level-up popup's
	# generic pool (damage/cooldown/etc.), which was never tier-capped.
	if element == UpgradeResource.ElementType.PHYSICAL:
		return 6
	if element == UpgradeResource.ElementType.CLASS:
		return 3  # (2026-07-21) the per-class active skill line -- see CharacterClasses.CLASSES "skills"
	return 5


func _on_choice_selected(index: int) -> void:
	if index >= _pending_choices.size():
		return
	AudioManager.play_ui("ui_click")
	player.apply_element_upgrade(_pending_choices[index])
	panel.visible = false
	GameManager.request_unpause("wave_upgrade")
