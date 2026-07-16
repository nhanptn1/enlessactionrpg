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
const ICE_BURST_SPEED := 14.0       # 4 frames read as one quick radiating spike burst (~0.3s)
const ICE_WALL_NOVA_SPEED := 13.0   # 5 frames read as a bigger "spin-up then shatter" (~0.4s)
const BURST_TARGET_DIAMETER_MULT := 2.2  # matches fire_explosion()'s own radius-to-sprite-width ratio

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
	shape.polygon = _circle_polygon(radius)
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
	var target_scale: float = (radius * 2.2) / sprite.texture.get_width()
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
	# Frozen Burst: a real 4-frame radiating ice-spike burst (from the supplied
	# "ice brust.png" reference sheet) instead of flash_burst()+ice_shards(),
	# scaled to the hit's burst radius -- same treatment Fire's Explosive
	# Volley got via fire_explosion().
	_play_burst_animation(_get_ice_burst_frames(), pos, radius, host)


static func ice_wall_nova_burst(pos: Vector2, radius: float, host: Node) -> void:
	# Ice Wall Nova: a bigger 5-frame swirl-to-shatter animation (from the
	# supplied "ice wall nova.png" reference sheet), distinct from Frozen
	# Burst's own art -- matches this skill's much larger burst_radius and
	# tier-3 weight with a more elaborate payoff.
	_play_burst_animation(_get_ice_wall_nova_frames(), pos, radius, host)


static func _play_burst_animation(frames: SpriteFrames, pos: Vector2, radius: float, host: Node) -> void:
	if not is_instance_valid(host):
		return
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.animation = &"burst"
	var first_tex: Texture2D = frames.get_frame_texture(&"burst", 0)
	sprite.scale = Vector2.ONE * (radius * BURST_TARGET_DIAMETER_MULT) / first_tex.get_width()
	sprite.global_position = pos
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


static func spark_burst(pos: Vector2, radius: float, host: Node) -> void:
	# Chain Spark's landing-node punch, and Thunder Storm's ground-impact --
	# a real 4-frame electric X-burst (from the supplied "chain spark.png"
	# reference) shared by both skills since they're the same "electric
	# discharge" moment, just triggered at different scales from different
	# call sites (Projectile._apply_chain() / player.gd's _fire_area_strike()).
	_play_burst_animation(_get_spark_burst_frames(), pos, radius, host)


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
