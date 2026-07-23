extends Node2D
class_name LivingBackground

# (2026-07-23) The whole endless run used to render against ONE static
# background sprite, so wave 60 looked identical to wave 1 and nothing conveyed
# descent or progression. This replaces it with a living backdrop, built
# entirely from the one existing texture plus procedural drawing -- no new art:
#   1. the arena texture scrolls downward and wraps seamlessly (two stacked
#      copies), matching the direction enemies fall, so the screen reads as
#      continuously descending;
#   2. two procedural parallax mote layers drift at different speeds/sizes for
#      real depth;
#   3. an atmosphere tint that shifts every boss cycle (10 waves), so pushing
#      deeper visibly changes the world instead of only the wave counter.

const BG_TEXTURE := "res://art/backgrounds/background_arena.png"
const SCREEN_SIZE := Vector2(720, 1440)  # generous vertical cover so the wrap seam is always off-screen

const SCROLL_SPEED := 14.0        # px/sec downward -- slow; it should read as drift, not motion sickness
const NEAR_MOTES := 26
const FAR_MOTES := 34
const NEAR_MOTE_SPEED := 26.0
const FAR_MOTE_SPEED := 9.0
const NEAR_MOTE_RADIUS := 2.6
const FAR_MOTE_RADIUS := 1.5
const TINT_FADE_TIME := 2.5       # seconds to cross-fade into a new cycle's atmosphere

# One atmosphere per boss cycle, cycling forever. Deliberately low-saturation
# multiplies -- the arena art has to stay readable behind gameplay, so these
# grade it rather than repaint it.
const CYCLE_TINTS: Array[Color] = [
	Color(1.00, 1.00, 1.00),  # cycle 1 -- the arena as authored
	Color(0.82, 0.88, 1.05),  # 2 moonlit
	Color(1.05, 0.86, 0.74),  # 3 dusk
	Color(0.78, 0.95, 0.86),  # 4 verdant
	Color(1.02, 0.78, 0.86),  # 5 blood
	Color(0.80, 0.82, 0.98),  # 6 deep night
]

var _sprites: Array[Sprite2D] = []
var _near: Array[Vector2] = []
var _far: Array[Vector2] = []
var _scroll := 0.0
var _tint_tween: Tween


func _ready() -> void:
	z_index = -100  # behind every gameplay actor
	var tex: Texture2D = load(BG_TEXTURE)
	var h: float = tex.get_height() if tex != null else SCREEN_SIZE.y
	# Two stacked copies, one directly above the other: as the pair scrolls
	# down, whichever leaves the bottom is lifted a full texture-height back to
	# the top, so the loop never shows a seam or a gap.
	for i in 2:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = true
		s.position = Vector2(0.0, -float(i) * h)
		add_child(s)
		_sprites.append(s)
	_seed_motes()
	SignalBus.wave_started.connect(_on_wave_started)


func _seed_motes() -> void:
	# Seeded from the screen box, not the texture, so density is predictable
	# regardless of what art the background happens to be.
	for _i in NEAR_MOTES:
		_near.append(Vector2(randf_range(-SCREEN_SIZE.x * 0.5, SCREEN_SIZE.x * 0.5), randf_range(-SCREEN_SIZE.y * 0.5, SCREEN_SIZE.y * 0.5)))
	for _i in FAR_MOTES:
		_far.append(Vector2(randf_range(-SCREEN_SIZE.x * 0.5, SCREEN_SIZE.x * 0.5), randf_range(-SCREEN_SIZE.y * 0.5, SCREEN_SIZE.y * 0.5)))


func _process(delta: float) -> void:
	var tex_h: float = _sprites[0].texture.get_height() if not _sprites.is_empty() and _sprites[0].texture != null else SCREEN_SIZE.y
	_scroll += SCROLL_SPEED * delta
	if _scroll >= tex_h:
		_scroll -= tex_h  # wrap the accumulator too, or it grows unbounded across a long run
	for i in _sprites.size():
		_sprites[i].position.y = _scroll - float(i) * tex_h
	_advance(_near, NEAR_MOTE_SPEED * delta)
	_advance(_far, FAR_MOTE_SPEED * delta)
	queue_redraw()


func _advance(motes: Array, dy: float) -> void:
	var top := -SCREEN_SIZE.y * 0.5
	var bottom := SCREEN_SIZE.y * 0.5
	for i in motes.size():
		var p: Vector2 = motes[i]
		p.y += dy
		if p.y > bottom:
			# Recycle to the top at a fresh x, so the field never repeats a
			# recognisable pattern on long runs.
			p.y = top
			p.x = randf_range(-SCREEN_SIZE.x * 0.5, SCREEN_SIZE.x * 0.5)
		motes[i] = p


func _on_wave_started(wave_number: int, _is_boss: bool) -> void:
	# Atmosphere advances once per boss cycle (every 10 waves) and loops.
	var cycle: int = int(max(0, wave_number - 1)) / 10
	var target: Color = CYCLE_TINTS[cycle % CYCLE_TINTS.size()]
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	_tint_tween = create_tween()
	_tint_tween.set_parallel(true)
	for s in _sprites:
		_tint_tween.tween_property(s, "modulate", target, TINT_FADE_TIME)


func _draw() -> void:
	for p in _far:
		draw_circle(p, FAR_MOTE_RADIUS, Color(1, 1, 1, 0.10))
	for p in _near:
		draw_circle(p, NEAR_MOTE_RADIUS, Color(1, 1, 1, 0.17))
