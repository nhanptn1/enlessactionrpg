extends RefCounted
class_name ImpactVFX
## Procedural elemental impact/cast effects -- no dedicated VFX art exists yet,
## so these build simple shapes (Polygon2D/Line2D) and animate them with
## Tweens, matching this project's established no-art-yet fallback pattern
## (item_icon.gd, skill_icon.gd draw their own art the same way). All static,
## no state of their own -- mirrors StatusEffects/Telegraph's convention.

const SHARD_COUNT := 6
const SHARD_COLOR := Color(0.75, 0.95, 1.0, 0.9)
const CHAIN_SEGMENTS := 5
const CHAIN_JITTER := 14.0
const CHAIN_WIDTH := 3.0

const FIRE_EXPLOSION_FRAME_1 := preload("res://art/vfx/fire_explosion_01.png")
const FIRE_EXPLOSION_FRAME_2 := preload("res://art/vfx/fire_explosion_02.png")
const METEOR_FRAME_PATHS := [
	"res://art/vfx/meteor_burning_rain_01.png",
	"res://art/vfx/meteor_burning_rain_02.png",
	"res://art/vfx/meteor_burning_rain_03.png",
	"res://art/vfx/meteor_burning_rain_04.png",
]
const METEOR_RENDER_SCALE := 0.09

const ICE_BURST_FRAME_PATHS := [
	"res://art/vfx/ice_burst_01.png",
	"res://art/vfx/ice_burst_02.png",
	"res://art/vfx/ice_burst_03.png",
	"res://art/vfx/ice_burst_04.png",
]
const ICE_WALL_NOVA_FRAME_PATHS := [
	"res://art/vfx/ice_wall_nova_01.png",
	"res://art/vfx/ice_wall_nova_02.png",
	"res://art/vfx/ice_wall_nova_03.png",
	"res://art/vfx/ice_wall_nova_04.png",
	"res://art/vfx/ice_wall_nova_05.png",
]
# (2026-07-23) Frostfire fusion, extracted from the user-supplied
# "fire_frost.png" sheet by scripts/tools/extract_frostfire.gd. Real art for
# the Fire+Frost combo, which until now resolved with a generic
# flash_burst + ice_burst + fire_explosion stack that looked like ordinary chip
# damage. Like the ice_burst sheet this is DIRECTIONAL (an ice bolt sheathed in
# flame, travelling rightward), so it gets the same -90 degrees correction to
# erupt upward from the impact point rather than smear sideways.
const FROSTFIRE_BOLT_FRAME_PATHS := [
	"res://art/vfx/frostfire_bolt_01.png",
	"res://art/vfx/frostfire_bolt_02.png",
	"res://art/vfx/frostfire_bolt_03.png",
	"res://art/vfx/frostfire_bolt_04.png",
]
const FROSTFIRE_BOLT_SPEED := 15.0  # 4 frames, ~0.27s -- a snappy detonation, not a lingering effect
# (2026-07-23) Superconductor fusion, extracted from "frost_lightning.png"
# (a 2x2 sheet -- see extract_vfx_sheet.gd). Unlike the Frostfire bolt this art
# is radially symmetric (ice crystals caged in arcs that reach out in every
# direction), so it needs NO rotation correction.
const SUPERCONDUCTOR_ARC_FRAME_PATHS := [
	"res://art/vfx/superconductor_arc_01.png",
	"res://art/vfx/superconductor_arc_02.png",
	"res://art/vfx/superconductor_arc_03.png",
	"res://art/vfx/superconductor_arc_04.png",
]
const SUPERCONDUCTOR_ARC_SPEED := 15.0
# (2026-07-23) Overload fusion, extracted from "fire_lightning.png". FIVE
# frames, not four: a fire/lightning beam that winds up and then detonates, so
# the extra frame is the payoff. Drawn unrotated -- the frames build
# left-to-right but the final blast (which is what actually reads at speed) is
# symmetric, so a rotation would only fight the explosion's own shape.
# (2026-07-24) Per-class impact art, from the user-supplied class-skill sheets.
# Before this every class shared one procedural coloured flash, so a Sniper's
# heavy single shot and a Ranger's volley landed identically apart from hue.
# Each class now resolves to its own burst; a class with no sheet yet falls back
# to the flash rather than erroring, so Juggernaut and Trapper keep working
# until their art arrives.
const CLASS_BURST_FRAME_PATHS := {
	"ranger": ["res://art/vfx/class_ranger_01.png", "res://art/vfx/class_ranger_05.png"],
	"sniper": ["res://art/vfx/class_sniper_04.png"],
	"elementalist": ["res://art/vfx/class_elementalist_04.png"],
}
const CLASS_BURST_SPEED := 14.0
static var _class_burst_frames: Dictionary = {}


# (2026-07-24) Real arc art for a chain jump, where chain_bolt() draws a
# procedural jagged line. Only the Elementalist has arc art so far; anything
# else keeps the procedural bolt, which is why this is a lookup rather than a
# replacement of chain_bolt().
const CLASS_CHAIN_ARC := {
	"elementalist": "res://art/vfx/class_elementalist_02.png",
}
const CHAIN_ARC_FADE := 0.22
static var _class_chain_arc_tex: Dictionary = {}


static func has_class_chain_arc(class_id: String) -> bool:
	return CLASS_CHAIN_ARC.has(class_id)


static func class_chain_arc(class_id: String, from_pos: Vector2, to_pos: Vector2, host: Node) -> void:
	if not CLASS_CHAIN_ARC.has(class_id) or not is_instance_valid(host):
		return
	if not _class_chain_arc_tex.has(class_id):
		_class_chain_arc_tex[class_id] = load(CLASS_CHAIN_ARC[class_id])
	var tex: Texture2D = _class_chain_arc_tex[class_id]
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.global_position = (from_pos + to_pos) / 2.0
	sprite.rotation = (to_pos - from_pos).angle()
	# Stretched along the jump so the arc actually spans the two enemies rather
	# than sitting at a fixed size between them; height is scaled by the same
	# factor, capped so a long jump doesn't produce an absurdly fat bolt.
	var span: float = maxf(from_pos.distance_to(to_pos), 1.0)
	var sx: float = span / float(tex.get_width())
	sprite.scale = Vector2(sx, minf(sx, 1.0))
	host.get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, CHAIN_ARC_FADE)
	tween.tween_callback(sprite.queue_free)


static func has_class_burst(class_id: String) -> bool:
	return CLASS_BURST_FRAME_PATHS.has(class_id)


static func class_burst(class_id: String, pos: Vector2, radius: float, host: Node) -> void:
	if not CLASS_BURST_FRAME_PATHS.has(class_id):
		return
	if not _class_burst_frames.has(class_id):
		_class_burst_frames[class_id] = _build_burst_frames(
			CLASS_BURST_FRAME_PATHS[class_id], CLASS_BURST_SPEED
		)
	_play_burst_animation(_class_burst_frames[class_id], pos, radius, host)


const OVERLOAD_BURST_FRAME_PATHS := [
	"res://art/vfx/overload_burst_01.png",
	"res://art/vfx/overload_burst_02.png",
	"res://art/vfx/overload_burst_03.png",
	"res://art/vfx/overload_burst_04.png",
	"res://art/vfx/overload_burst_05.png",
]
const OVERLOAD_BURST_SPEED := 17.0  # 5 frames, ~0.3s -- slightly faster so the wind-up doesn't drag
const ICE_BURST_SPEED := 14.0       # 4 frames read as one quick radiating spike burst (~0.3s)
const ICE_WALL_NOVA_SPEED := 13.0   # 5 frames read as a bigger "spin-up then shatter" (~0.4s)
const BURST_TARGET_DIAMETER_MULT := 2.2  # matches fire_explosion()'s own radius-to-sprite-width ratio
# (2026-07-23) A single readability lever over EVERY burst visual. Effects were
# drawn at 2.2x their radius, so the biggest elemental skill (burst_radius 170)
# covered 374px of a 720px-wide screen and a fusion covered 440px -- they read
# as screen-filling noise rather than as distinct hits, especially with several
# landing at once. Scaling the DRAW only (never the radius itself) shrinks them
# for readability without nerfing a single skill's actual damage area.
# At 0.68: largest elemental draws ~254px (35% of width), a fusion ~300px
# (42%), so fusions still clearly out-size normal skills without covering the
# screen. Tune this one number if effects still feel too big or too small.
const BURST_VISUAL_SCALE := 0.68

const SPARK_BURST_FRAME_PATHS := [
	"res://art/vfx/spark_burst_01.png",
	"res://art/vfx/spark_burst_02.png",
	"res://art/vfx/spark_burst_03.png",
	"res://art/vfx/spark_burst_04.png",
]
const LIGHTNING_STRIKE_FRAME_PATHS := [
	"res://art/vfx/lightning_strike_01.png",
	"res://art/vfx/lightning_strike_02.png",
	"res://art/vfx/lightning_strike_03.png",
	"res://art/vfx/lightning_strike_04.png",
	"res://art/vfx/lightning_strike_05.png",
]
const SPARK_BURST_SPEED := 16.0        # 4 frames read as one quick electric discharge (~0.25s)
const LIGHTNING_STRIKE_SPEED := 18.0   # fast crackle while the strike telegraph builds in
const LIGHTNING_STRIKE_HEIGHT := 300.0 # (2026-07-16) was 480 -- user feedback that Thunder Storm's cast visual read as too big, especially with 3 zones on screen at once
const CHAIN_SPARK_BURST_RADIUS := 32.0 # Chain Spark has no burst_radius stat -- fixed visual size for its per-node punch

const ARROW_RAIN_FALL_FRAME_PATHS := [
	"res://art/vfx/arrow_rain_begins.png",
	"res://art/vfx/arrow_rain_barrage.png",
	"res://art/vfx/arrow_rain_falling.png",
]
const ARROW_RAIN_IMPACT_FRAME_PATHS := [
	"res://art/vfx/arrow_rain_impact.png",
]
const ARROW_RAIN_IMPACT_SPEED := 3.5    # 1 frame, held briefly as a quick impact flash (~0.28s)
const ARROW_RAIN_FALL_SPEED := 5.0      # 3 frames span 0.6s, matching this fire mode's typical telegraph_time (e.g. burning_rain.tres/thunder_storm.tres)
const ARROW_RAIN_FALL_HEIGHT := 280.0   # (2026-07-16) was 420 -- user feedback that Arrow Rain's cast visual read as too big, especially with 3 zones on screen at once

static var _meteor_frames: SpriteFrames = null
static var _ice_burst_frames: SpriteFrames = null
static var _ice_wall_nova_frames: SpriteFrames = null
static var _spark_burst_frames: SpriteFrames = null
static var _lightning_strike_frames: SpriteFrames = null
static var _arrow_rain_fall_frames: SpriteFrames = null
static var _arrow_rain_impact_frames: SpriteFrames = null


static func flash_burst(pos: Vector2, radius: float, color: Color, host: Node) -> void:
	# A quick expanding, fading ring -- used for every burst_radius hit
	# (Explosive Volley, Frozen Burst, Ice Wall Nova) and for area-strike
	# impacts (Arrow Rain, Burning Rain, Thunder Storm).
	if not is_instance_valid(host):
		return
	var shape := Polygon2D.new()
	shape.color = color
	shape.polygon = _circle_polygon(radius * BURST_VISUAL_SCALE)  # same readability scale as the animated bursts, so ring and art stay in step
	shape.global_position = pos
	shape.scale = Vector2(0.25, 0.25)
	host.get_tree().current_scene.add_child(shape)
	var tween := shape.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shape, "scale", Vector2.ONE * 1.1, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(shape, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(shape.queue_free)


static func ice_shards(pos: Vector2, host: Node) -> void:
	# Frost's flourish on top of flash_burst -- a handful of small shard
	# triangles fly outward from the hit point and fade, a "shatter" look.
	if not is_instance_valid(host):
		return
	for _i in SHARD_COUNT:
		var angle := randf() * TAU
		var dist := randf_range(18.0, 34.0)
		var shard := Polygon2D.new()
		shard.color = SHARD_COLOR
		shard.polygon = PackedVector2Array([Vector2(0, -6), Vector2(3, 4), Vector2(-3, 4)])
		shard.rotation = angle
		shard.global_position = pos
		host.get_tree().current_scene.add_child(shard)
		var target: Vector2 = pos + Vector2(cos(angle), sin(angle)) * dist
		var tween := shard.create_tween()
		tween.set_parallel(true)
		tween.tween_property(shard, "global_position", target, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(shard, "modulate:a", 0.0, 0.32)
		tween.chain().tween_callback(shard.queue_free)


static func chain_bolt(from_pos: Vector2, to_pos: Vector2, color: Color, host: Node) -> void:
	# Chain Spark: a brief jagged line connecting two chained hits, so the
	# chain actually reads as lightning jumping between enemies.
	if not is_instance_valid(host):
		return
	var line := Line2D.new()
	line.width = CHAIN_WIDTH
	line.default_color = color
	var points := PackedVector2Array()
	points.append(from_pos)
	for i in range(1, CHAIN_SEGMENTS):
		var t := float(i) / CHAIN_SEGMENTS
		var base: Vector2 = from_pos.lerp(to_pos, t)
		var perp := (to_pos - from_pos).normalized().rotated(PI / 2.0)
		base += perp * randf_range(-CHAIN_JITTER, CHAIN_JITTER)
		points.append(base)
	points.append(to_pos)
	line.points = points
	host.get_tree().current_scene.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(line.queue_free)


static func falling_strike(target_pos: Vector2, duration: float, color: Color, host: Node) -> void:
	# Burning Rain / Thunder Storm / Arrow Rain: a visible ball falls from
	# above onto the telegraphed zone, timed to land exactly when the
	# telegraph resolves, instead of just a warning circle with no descent.
	if not is_instance_valid(host):
		return
	var start_pos: Vector2 = target_pos + Vector2(randf_range(-20.0, 20.0), -420.0)
	var visual := Polygon2D.new()
	visual.color = color
	visual.polygon = _circle_polygon(14.0)
	visual.global_position = start_pos
	host.get_tree().current_scene.add_child(visual)
	var tween := visual.create_tween()
	tween.tween_property(visual, "global_position", target_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(visual.queue_free)


static func fire_explosion(pos: Vector2, radius: float, host: Node) -> void:
	# Real 2-frame explosion art (Explosive Volley's burst + Burning Rain's
	# impact) instead of the plain procedural flash_burst -- a small forming
	# spark that snaps to the full blast, scaled to the hit's burst radius.
	if not is_instance_valid(host):
		return
	var sprite := Sprite2D.new()
	sprite.texture = FIRE_EXPLOSION_FRAME_1
	sprite.global_position = pos
	var target_scale: float = (radius * BURST_TARGET_DIAMETER_MULT * BURST_VISUAL_SCALE) / sprite.texture.get_width()  # was a hardcoded 2.2 -- now shares the same readability scale as every other burst
	sprite.scale = Vector2.ONE * target_scale * 0.35
	host.get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector2.ONE * target_scale * 0.7, 0.05)
	tween.tween_callback(func(): sprite.texture = FIRE_EXPLOSION_FRAME_2)
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE * target_scale, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(sprite.queue_free)


static func fire_meteor_fall(target_pos: Vector2, duration: float, host: Node) -> void:
	# Burning Rain's own falling visual -- a real roaring meteor sprite instead
	# of falling_strike()'s plain circle, rotated nose-down (the art's "head"
	# faces its own +X, so PI/2 points it toward +Y/down) so it reads as
	# something dropping out of the sky rather than sliding in sideways.
	if not is_instance_valid(host):
		return
	var start_pos: Vector2 = target_pos + Vector2(randf_range(-20.0, 20.0), -420.0)
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _get_meteor_frames()
	sprite.animation = &"fall"
	sprite.play()
	sprite.rotation = PI / 2.0
	sprite.scale = Vector2.ONE * METEOR_RENDER_SCALE
	sprite.global_position = start_pos
	host.get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "global_position", target_pos, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(sprite.queue_free)


static func ice_burst(pos: Vector2, radius: float, host: Node) -> void:
	# Frozen Burst: a real 4-frame ice-spike burst (from the supplied
	# "ice brust.png" reference sheet) instead of flash_burst()+ice_shards(),
	# scaled to the hit's burst radius -- same treatment Fire's Explosive
	# Volley got via fire_explosion(). (2026-07-16) Unlike fire_explosion()/
	# ice_wall_nova_burst()'s art, this reference sheet turned out to be a
	# directional spike FAN (all spikes thrust rightward, not radiating in
	# every direction) rather than a true radial burst -- confirmed by
	# comparing directly against the other two, which are genuinely
	# omnidirectional. Left unrotated it always read as "heading left to
	# right" no matter where the hit landed (user report). Rotated -90° so
	# the fan erupts upward from the impact point instead, which reads as
	# intentional in this vertical shooter (enemies are always above) rather
	# than a random sideways smear.
	_play_burst_animation(_get_ice_burst_frames(), pos, radius, host, -PI / 2.0)


static func frostfire_bolt(pos: Vector2, radius: float, host: Node) -> void:
	# The Frostfire fusion's own signature detonation. Rotated -90 degrees for
	# the same reason ice_burst() is: the source sheet is a rightward-travelling
	# bolt, and left unrotated it reads as a sideways smear regardless of where
	# the hit landed. Erupting upward suits this vertical shooter (enemies are
	# always above the player).
	_play_burst_animation(_get_frostfire_bolt_frames(), pos, radius, host, -PI / 2.0)


static func _get_frostfire_bolt_frames() -> SpriteFrames:
	return _build_burst_frames(FROSTFIRE_BOLT_FRAME_PATHS, FROSTFIRE_BOLT_SPEED)


static func superconductor_arc(pos: Vector2, radius: float, host: Node) -> void:
	# The Superconductor fusion's signature detonation. Radially symmetric, so
	# unlike frostfire_bolt()/ice_burst() it is drawn unrotated.
	_play_burst_animation(_get_superconductor_arc_frames(), pos, radius, host)


static func _get_superconductor_arc_frames() -> SpriteFrames:
	return _build_burst_frames(SUPERCONDUCTOR_ARC_FRAME_PATHS, SUPERCONDUCTOR_ARC_SPEED)


static func overload_burst(pos: Vector2, radius: float, host: Node) -> void:
	# The Overload fusion's signature detonation -- a fire/lightning wind-up
	# into a symmetric blast. Unrotated; see the const block above.
	_play_burst_animation(_get_overload_burst_frames(), pos, radius, host)


static func _get_overload_burst_frames() -> SpriteFrames:
	return _build_burst_frames(OVERLOAD_BURST_FRAME_PATHS, OVERLOAD_BURST_SPEED)


static func ice_wall_nova_burst(pos: Vector2, radius: float, host: Node) -> void:
	# Ice Wall Nova: a bigger 5-frame swirl-to-shatter animation (from the
	# supplied "ice wall nova.png" reference sheet), distinct from Frozen
	# Burst's own art -- matches this skill's much larger burst_radius and
	# tier-3 weight with a more elaborate payoff. Genuinely radially
	# symmetric (confirmed visually), so no rotation correction needed.
	_play_burst_animation(_get_ice_wall_nova_frames(), pos, radius, host)


static func _play_burst_animation(frames: SpriteFrames, pos: Vector2, radius: float, host: Node, rotation: float = 0.0, tint: Color = Color.WHITE) -> void:
	if not is_instance_valid(host):
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"burst"
	# (2026-07-24) Optional tint so one burst animation can serve more than one
	# element -- the spark burst is shared by Lightning's Chain Spark and the
	# physical line's Chain Arrow, and the latter must not read as electric.
	sprite.modulate = tint
	var first_tex: Texture2D = frames.get_frame_texture(&"burst", 0)
	sprite.scale = Vector2.ONE * (radius * BURST_TARGET_DIAMETER_MULT * BURST_VISUAL_SCALE) / first_tex.get_width()
	sprite.global_position = pos
	sprite.rotation = rotation
	host.get_tree().current_scene.add_child(sprite)
	sprite.play()
	sprite.animation_finished.connect(sprite.queue_free)


static func _get_ice_burst_frames() -> SpriteFrames:
	if _ice_burst_frames == null:
		_ice_burst_frames = _build_burst_frames(ICE_BURST_FRAME_PATHS, ICE_BURST_SPEED)
	return _ice_burst_frames


static func _get_ice_wall_nova_frames() -> SpriteFrames:
	if _ice_wall_nova_frames == null:
		_ice_wall_nova_frames = _build_burst_frames(ICE_WALL_NOVA_FRAME_PATHS, ICE_WALL_NOVA_SPEED)
	return _ice_wall_nova_frames


static func _build_burst_frames(paths: Array, speed: float, anim_name: String = "burst", loop: bool = false) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, speed)
	for path in paths:
		frames.add_frame(anim_name, load(path))
	return frames


static func spark_burst(pos: Vector2, radius: float, host: Node, tint: Color = Color.WHITE) -> void:
	# Chain Spark's landing-node punch, and Thunder Storm's ground-impact --
	# a real 4-frame electric X-burst (from the supplied "chain spark.png"
	# reference) shared by both skills since they're the same "electric
	# discharge" moment, just triggered at different scales from different
	# call sites (Projectile._apply_chain() / player.gd's _fire_area_strike()).
	_play_burst_animation(_get_spark_burst_frames(), pos, radius, host, 0.0, tint)


static func lightning_strike_fall(target_pos: Vector2, duration: float, host: Node) -> void:
	# Thunder Storm's own falling visual -- a real vertical lightning-bolt
	# column (from the supplied "thunder storm.png" reference), anchored at
	# its base on the impact point and crackling in over the telegraph
	# window, instead of falling_strike()'s plain descending circle. Fades
	# in over the first half of `duration`, holds fully lit for the second
	# half, then removes itself right as the telegraph resolves -- same
	# timing contract falling_strike()/fire_meteor_fall() already use.
	if not is_instance_valid(host):
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _get_lightning_strike_frames()
	sprite.animation = &"crackle"
	sprite.play()
	var first_tex: Texture2D = sprite.sprite_frames.get_frame_texture(&"crackle", 0)
	var s: float = LIGHTNING_STRIKE_HEIGHT / first_tex.get_height()
	sprite.scale = Vector2.ONE * s
	sprite.offset.y = -first_tex.get_height() / 2.0  # anchor the bolt's bottom edge at target_pos
	sprite.global_position = target_pos
	sprite.modulate.a = 0.0
	host.get_tree().current_scene.add_child(sprite)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "modulate:a", 1.0, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(duration * 0.5)
	tween.tween_callback(sprite.queue_free)


static func _get_spark_burst_frames() -> SpriteFrames:
	if _spark_burst_frames == null:
		_spark_burst_frames = _build_burst_frames(SPARK_BURST_FRAME_PATHS, SPARK_BURST_SPEED)
	return _spark_burst_frames


static func _get_lightning_strike_frames() -> SpriteFrames:
	if _lightning_strike_frames == null:
		_lightning_strike_frames = _build_burst_frames(LIGHTNING_STRIKE_FRAME_PATHS, LIGHTNING_STRIKE_SPEED, "crackle", true)
	return _lightning_strike_frames


static func arrow_rain_fall(target_pos: Vector2, duration: float, host: Node) -> void:
	# Basic-line Arrow Rain's own telegraph visual -- a real 3-frame sequence
	# (2026-07-16: re-extracted from a simpler supplied reference,
	# "arrow-rain-simple.png" -- arrows actually descending through the air,
	# closer to the ground each frame, replacing the earlier art's "column of
	# arrows growing up out of the ground" abstraction) instead of
	# falling_strike()'s plain descending ball. Bottom-anchored so the ground
	# marker stays put while the arrows visibly approach it frame to frame.
	# The reference sheet's own standalone telegraph-ring frame was dropped --
	# the game already draws its own ground marker via Telegraph.show_circle()
	# at this exact spot, so a second ring baked into the sprite would double up.
	# `duration` isn't used to rescale the animation (fixed pre-tuned speed
	# instead, like lightning_strike_fall()) -- _fire_arrow_rain() fires
	# several zones from one shared cached SpriteFrames resource, and mutating
	# its speed per-call would fight itself across simultaneously-playing
	# instances. Kept in the signature to match fire_meteor_fall()'s/
	# lightning_strike_fall()'s call shape from _fire_area_strike().
	if not is_instance_valid(host):
		return
	var frames := _get_arrow_rain_fall_frames()
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"rise"
	sprite.play()
	var first_tex: Texture2D = frames.get_frame_texture(&"rise", 0)
	var s: float = ARROW_RAIN_FALL_HEIGHT / first_tex.get_height()
	sprite.scale = Vector2.ONE * s
	sprite.offset.y = -first_tex.get_height() / 2.0  # anchor the ground marker at target_pos
	sprite.global_position = target_pos
	host.get_tree().current_scene.add_child(sprite)
	sprite.animation_finished.connect(sprite.queue_free)


static func arrow_rain_impact(pos: Vector2, radius: float, host: Node) -> void:
	# Basic-line Arrow Rain's impact -- a real impact-burst frame (from the
	# same "arrow-rain-simple.png" reference as arrow_rain_fall() above)
	# instead of flash_burst()'s plain ring.
	_play_burst_animation(_get_arrow_rain_impact_frames(), pos, radius, host)


static func _get_arrow_rain_fall_frames() -> SpriteFrames:
	if _arrow_rain_fall_frames == null:
		_arrow_rain_fall_frames = _build_burst_frames(ARROW_RAIN_FALL_FRAME_PATHS, ARROW_RAIN_FALL_SPEED, "rise", false)
	return _arrow_rain_fall_frames


static func _get_arrow_rain_impact_frames() -> SpriteFrames:
	if _arrow_rain_impact_frames == null:
		_arrow_rain_impact_frames = _build_burst_frames(ARROW_RAIN_IMPACT_FRAME_PATHS, ARROW_RAIN_IMPACT_SPEED)
	return _arrow_rain_impact_frames


static func _get_meteor_frames() -> SpriteFrames:
	if _meteor_frames == null:
		var frames := SpriteFrames.new()
		frames.remove_animation("default")
		frames.add_animation("fall")
		frames.set_animation_loop("fall", true)
		frames.set_animation_speed("fall", 10.0)
		for path in METEOR_FRAME_PATHS:
			frames.add_frame("fall", load(path))
		_meteor_frames = frames
	return _meteor_frames


static func _circle_polygon(radius: float, segments: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		pts.append(Vector2(cos(angle), sin(angle)) * radius)
	return pts


# (2026-07-16) Boss attacks below -- every generic-shape boss attack
# (root_slam/vine_whip/poison_burst/aimed_shot) used to share one identical
# flash_burst() ring regardless of what the attack actually was, which read
# as "the same colored circle every time" -- user: "boss attack still not
# real attack, still prototype." No dedicated boss attack art exists (same
# constraint as everything else in this file), so these are each a distinct
# procedural shape matching the attack's own identity instead of one shared
# template.

static func ground_spikes(pos: Vector2, radius: float, host: Node) -> void:
	# Root Slam: a handful of jagged brown spikes erupt from the ground within
	# the hit radius and settle back down, instead of a flat colored ring.
	if not is_instance_valid(host):
		return
	var count := 6
	for i in count:
		var angle: float = TAU * i / count + randf_range(-0.25, 0.25)
		var dist: float = radius * randf_range(0.25, 0.85)
		var spike_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * dist
		var spike_height: float = randf_range(16.0, 26.0)
		var spike := Polygon2D.new()
		spike.color = Color(0.42, 0.3, 0.16, 1.0)
		spike.polygon = PackedVector2Array([Vector2(-4, 0), Vector2(4, 0), Vector2(0, -spike_height)])
		spike.global_position = spike_pos
		spike.scale = Vector2(1.0, 0.05)
		host.get_tree().current_scene.add_child(spike)
		var tween := spike.create_tween()
		tween.tween_property(spike, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(0.18)
		tween.tween_property(spike, "modulate:a", 0.0, 0.22)
		tween.tween_callback(spike.queue_free)


static func whip_lash(from_pos: Vector2, to_pos: Vector2, host: Node) -> void:
	# Vine Whip: an actual curved lash line from the boss to the target
	# (a shallow bow, not a straight bar) that snaps thin and fades, instead
	# of a static translucent rectangle just appearing and vanishing.
	if not is_instance_valid(host):
		return
	var dir: Vector2 = (to_pos - from_pos).normalized()
	var normal: Vector2 = Vector2(-dir.y, dir.x) * (18.0 if randf() < 0.5 else -18.0)
	var mid: Vector2 = from_pos.lerp(to_pos, 0.5) + normal
	var line := Line2D.new()
	line.width = 10.0
	line.default_color = Color(0.3, 0.7, 0.25, 0.9)
	line.points = PackedVector2Array([from_pos, mid, to_pos])
	host.get_tree().current_scene.add_child(line)
	var tween := line.create_tween()
	tween.tween_property(line, "width", 3.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(line, "modulate:a", 0.0, 0.22)
	tween.tween_callback(line.queue_free)


static func poison_cloud(pos: Vector2, radius: float, host: Node) -> void:
	# Poison Burst: several small purple/green bubbles drift upward and fade
	# within the hit radius, reading as a toxic gas puff instead of one flat
	# purple ring.
	if not is_instance_valid(host):
		return
	var count := 8
	for i in count:
		var angle: float = randf_range(0.0, TAU)
		var dist: float = radius * randf_range(0.1, 0.8)
		var bubble_pos: Vector2 = pos + Vector2(cos(angle), sin(angle)) * dist
		var bubble_radius: float = randf_range(5.0, 11.0)
		var bubble := Polygon2D.new()
		bubble.color = Color(0.55, 0.2, 0.6, 0.75) if i % 2 == 0 else Color(0.35, 0.55, 0.25, 0.7)
		bubble.polygon = _circle_polygon(bubble_radius, 10)
		bubble.global_position = bubble_pos
		host.get_tree().current_scene.add_child(bubble)
		var rise: Vector2 = Vector2(randf_range(-10.0, 10.0), -randf_range(22.0, 40.0))
		var tween := bubble.create_tween()
		tween.set_parallel(true)
		tween.tween_property(bubble, "global_position", bubble_pos + rise, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(bubble, "modulate:a", 0.0, 0.5)
		tween.chain().tween_callback(bubble.queue_free)


static func arrow_shot(from_pos: Vector2, to_pos: Vector2, host: Node) -> void:
	# Dark Ranger's Aimed Shot: a real arrow-shaped polygon streaks from the
	# boss to the target right as the hit resolves, instead of an instant
	# translucent rectangle standing in for "an arrow was fired."
	if not is_instance_valid(host):
		return
	var arrow := Polygon2D.new()
	arrow.color = Color(0.6, 0.1, 0.1, 0.95)
	arrow.polygon = PackedVector2Array([Vector2(-14, -3), Vector2(6, -3), Vector2(6, -7), Vector2(16, 0), Vector2(6, 7), Vector2(6, 3), Vector2(-14, 3)])
	arrow.global_position = from_pos
	arrow.rotation = (to_pos - from_pos).angle()
	host.get_tree().current_scene.add_child(arrow)
	var tween := arrow.create_tween()
	tween.tween_property(arrow, "global_position", to_pos, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(arrow.queue_free)


# (2026-07-16) Fallen Knight (3rd boss) below -- same "each attack gets its
# own distinct procedural shape" convention as the section above.

static func sword_slash(pos: Vector2, direction: Vector2, host: Node) -> void:
	# Sword Slash, and Charge's landing hit: a bright crescent slash arc
	# oriented toward the strike direction, instead of a flat colored ring.
	if not is_instance_valid(host):
		return
	var slash := Polygon2D.new()
	slash.color = Color(0.85, 0.9, 0.95, 0.95)
	var arc_radius := 34.0
	var arc_span := deg_to_rad(70.0)
	var segments := 10
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a: float = -arc_span / 2.0 + arc_span * i / segments
		pts.append(Vector2(cos(a), sin(a)) * arc_radius)
	for i in segments + 1:
		var a: float = arc_span / 2.0 - arc_span * i / segments
		pts.append(Vector2(cos(a), sin(a)) * (arc_radius * 0.55))
	slash.polygon = pts
	slash.global_position = pos
	slash.rotation = direction.angle()
	host.get_tree().current_scene.add_child(slash)
	var tween := slash.create_tween()
	tween.set_parallel(true)
	tween.tween_property(slash, "scale", Vector2.ONE * 1.3, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(slash, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(slash.queue_free)


static func ground_shockwave(pos: Vector2, radius: float, host: Node) -> void:
	# Shockwave: a jagged cracked-ground burst that punches outward and
	# fades, distinct from flash_burst()'s smooth ring or ground_spikes()'s
	# vertical spikes.
	if not is_instance_valid(host):
		return
	var ring := Polygon2D.new()
	ring.color = Color(0.55, 0.5, 0.42, 0.85)
	var segments := 16
	var pts := PackedVector2Array()
	for i in segments:
		var a: float = TAU * i / segments
		var r: float = radius * (0.85 if i % 2 == 0 else 1.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	ring.polygon = pts
	ring.global_position = pos
	ring.scale = Vector2(0.3, 0.3)
	host.get_tree().current_scene.add_child(ring)
	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)


static func shield_flash(pos: Vector2, radius: float, host: Node) -> void:
	# Shield Burst: a bright hexagonal "shield" flash plus a few spark shards
	# radiating outward, reading as a metallic defensive burst rather than a
	# flat colored ring.
	if not is_instance_valid(host):
		return
	var burst := Polygon2D.new()
	burst.color = Color(0.75, 0.85, 1.0, 0.9)
	burst.polygon = _circle_polygon(radius * 0.5, 6)
	burst.global_position = pos
	host.get_tree().current_scene.add_child(burst)
	var burst_tween := burst.create_tween()
	burst_tween.set_parallel(true)
	burst_tween.tween_property(burst, "scale", Vector2.ONE * 1.6, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	burst_tween.tween_property(burst, "modulate:a", 0.0, 0.26)
	burst_tween.chain().tween_callback(burst.queue_free)
	var shard_count := 6
	for i in shard_count:
		var angle: float = TAU * i / shard_count
		var shard := Polygon2D.new()
		shard.color = Color(0.85, 0.92, 1.0, 0.9)
		shard.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(0, -14)])
		shard.global_position = pos
		shard.rotation = angle
		host.get_tree().current_scene.add_child(shard)
		var shard_tween := shard.create_tween()
		shard_tween.set_parallel(true)
		shard_tween.tween_property(shard, "global_position", pos + Vector2(cos(angle), sin(angle)) * radius * 0.6, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shard_tween.tween_property(shard, "modulate:a", 0.0, 0.22)
		shard_tween.chain().tween_callback(shard.queue_free)


# (2026-07-16) Demon Beast (4th boss) below.

static func claw_swipe(pos: Vector2, direction: Vector2, host: Node) -> void:
	# Claw Swipe: 3 parallel curved rake marks oriented toward the strike
	# direction, instead of Sword Slash's single crescent blade arc -- reads
	# as claws, not a weapon.
	if not is_instance_valid(host):
		return
	var offsets := [-10.0, 0.0, 10.0]
	for offset in offsets:
		var claw := Polygon2D.new()
		claw.color = Color(0.95, 0.85, 0.8, 0.95)
		var length := 30.0
		var curve := 6.0
		claw.polygon = PackedVector2Array([
			Vector2(-length * 0.5, offset - 2.0),
			Vector2(0.0, offset - 2.0 - curve),
			Vector2(length * 0.5, offset - 1.5),
			Vector2(length * 0.5, offset + 1.5),
			Vector2(0.0, offset + 2.0 + curve),
			Vector2(-length * 0.5, offset + 2.0),
		])
		claw.global_position = pos
		claw.rotation = direction.angle()
		host.get_tree().current_scene.add_child(claw)
		var tween := claw.create_tween()
		tween.set_parallel(true)
		tween.tween_property(claw, "scale", Vector2.ONE * 1.25, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(claw, "modulate:a", 0.0, 0.18)
		tween.chain().tween_callback(claw.queue_free)
