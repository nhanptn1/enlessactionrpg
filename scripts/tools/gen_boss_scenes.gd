extends SceneTree
## Regenerates the boss .tscn files with move / attack / death animations built
## from the extracted art. Run:
##   godot --headless --path . --script res://scripts/tools/gen_boss_scenes.gd
##
## (2026-07-23) Written as a tool rather than hand-editing four scenes: each
## boss has a different frame count per animation (the Fallen Knight's sheet
## yields 8, the others 4), plus the Forest Guardian keeps a `sapling_data`
## export. Generating from one spec keeps all four consistent instead of
## risking a silent hand-editing slip.
##
## (2026-07-24) The Guardian's attack row is no longer a special case: its
## burst VFX spray wide enough that gap detection merged two poses into one
## cut (3 frames from a 4-frame row, with slivers of neighbours attached), so
## extract_boss_sheet.gd now re-cuts that row with a declared column count --
## the same fix the Knight's slash trail and the Demon Beast's tail needed.
## All four bosses now have all three animations.

const BOSSES := [
	{
		"scene": "res://scenes/enemies/FallenKnight.tscn",
		"node": "FallenKnight",
		"prefix": "fallen_knight",
		"walk": 8, "attack": 8, "death": 8,
		"scale": "1.6", "walk_speed": "8.0",
		"props": ['attack_pattern_id = "fallen_knight"', "advances_to_lose_line = true"],
	},
	{
		"scene": "res://scenes/enemies/DarkRangerCommander.tscn",
		"node": "DarkRangerCommander",
		"prefix": "dark_ranger",
		"walk": 4, "attack": 4, "death": 4,
		"scale": "0.51", "walk_speed": "6.0",
		"props": ['attack_pattern_id = "dark_ranger_commander"', "advances_to_lose_line = true"],
	},
	{
		"scene": "res://scenes/enemies/DemonBeast.tscn",
		"node": "DemonBeast",
		"prefix": "demon_beast",
		"walk": 4, "attack": 4, "death": 4,
		"scale": "0.47", "walk_speed": "7.0",
		"props": ['attack_pattern_id = "demon_beast"', "advances_to_lose_line = true"],
	},
	{
		"scene": "res://scenes/enemies/CorruptedForestGuardian.tscn",
		"node": "CorruptedForestGuardian",
		"prefix": "forest_guardian",
		"walk": 4, "attack": 4, "death": 4,  # (2026-07-24) attack row recovered, see header
		"scale": "0.72", "walk_speed": "5.0",
		"extra_ext": ['[ext_resource type="Resource" path="res://resources/enemies/sapling.tres" id="3"]'],
		"props": ['sapling_data = ExtResource("3")', "advances_to_lose_line = true"],
	},
]


func _frames(prefix: String, count: int) -> String:
	var parts: Array[String] = []
	for i in range(1, count + 1):
		parts.append('{\n"duration": 1.0,\n"texture": ExtResource("%s%d")\n}' % [prefix, i])
	return ", ".join(parts)


func _anim(anim_name: String, prefix: String, count: int, loop: bool, speed: String) -> String:
	return '{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %s\n}' % [
		_frames(prefix, count), "true" if loop else "false", anim_name, speed,
	]


func _init() -> void:
	for cfg in BOSSES:
		_build(cfg)
	quit(0)


func _build(cfg: Dictionary) -> void:
	var walk: int = cfg["walk"]
	var attack: int = cfg["attack"]
	var death: int = cfg["death"]
	var extra_ext: Array = cfg.get("extra_ext", [])
	var lines: Array[String] = []
	var steps: int = 1 + extra_ext.size() + walk + attack + death + 2 + 1
	lines.append("[gd_scene load_steps=%d format=3]" % steps)
	lines.append("")
	lines.append('[ext_resource type="Script" path="res://scripts/systems/boss_base.gd" id="1"]')
	for e in extra_ext:
		lines.append(e)
	for pair in [["walk", "w", walk], ["attack", "a", attack], ["death", "d", death]]:
		for i in range(1, int(pair[2]) + 1):
			lines.append('[ext_resource type="Texture2D" path="res://art/bosses/%s_%s_%02d.png" id="%s%d"]' % [
				cfg["prefix"], pair[0], i, pair[1], i,
			])
	lines.append("")
	lines.append('[sub_resource type="CircleShape2D" id="CircleShape1"]')
	lines.append("radius = 16.0")
	lines.append("")
	lines.append('[sub_resource type="SpriteFrames" id="SpriteFrames1"]')
	var anims: Array[String] = []
	# Only emit animations that actually have frames -- an empty one would be
	# invalid, and BossBase._has_anim() treats a missing animation as "fall back
	# to the old behaviour", which is exactly right for the Guardian's attack.
	if attack > 0:
		anims.append(_anim("attack", "a", attack, false, "10.0"))
	if death > 0:
		anims.append(_anim("death", "d", death, false, "9.0"))
	anims.append(_anim("move", "w", walk, true, cfg["walk_speed"]))
	lines.append("animations = [%s]" % ", ".join(anims))
	lines.append("")
	lines.append('[node name="%s" type="CharacterBody2D"]' % cfg["node"])
	lines.append("collision_layer = 2")
	lines.append("collision_mask = 1")
	lines.append('script = ExtResource("1")')
	for p in cfg["props"]:
		lines.append(p)
	lines.append("")
	lines.append('[node name="Sprite" type="AnimatedSprite2D" parent="."]')
	lines.append('sprite_frames = SubResource("SpriteFrames1")')
	lines.append('animation = &"move"')
	lines.append("scale = Vector2(%s, %s)" % [cfg["scale"], cfg["scale"]])
	lines.append("")
	lines.append('[node name="Collision" type="CollisionShape2D" parent="."]')
	lines.append('shape = SubResource("CircleShape1")')

	var f := FileAccess.open(cfg["scene"], FileAccess.WRITE)
	if f == null:
		printerr("could not write %s" % cfg["scene"])
		return
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("%s: move=%d attack=%d death=%d" % [cfg["node"], walk, attack, death])
