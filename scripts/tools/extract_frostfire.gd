extends SceneTree
## One-off asset extractor. Run:
##   godot --headless --path . --script res://scripts/tools/extract_frostfire.gd
##
## (2026-07-23) Slices the user-supplied fire_frost.png sheet (4 frames of a
## fused fire+frost bolt, laid out left-to-right on transparency) into the
## project's established per-frame convention -- art/vfx/<effect>_01..04.png,
## same as arrow_fire_* / ice_burst_* were extracted.
##
## Every frame is cropped to the SAME rect (the union of all four frames'
## opaque bounds, plus a small pad) rather than to its own tight bounds. Tight
## per-frame crops would each have a different size and origin, so the bolt
## would visibly jitter and change scale as the animation cycled.

const SRC := "D:/WORK/PROJECT/GODOT/image/skills/fire_frost.png"
const OUT_PREFIX := "res://art/vfx/frostfire_bolt_"
const FRAMES := 4
const PAD := 4  # a few px of breathing room so edge glow isn't clipped

# The source sheets ship with the transparency CHECKERBOARD baked in as real
# opaque pixels (verified: 0% transparent), so it has to be keyed out -- the
# previously-extracted assets in art/vfx are ~89% transparent, so this is what
# the original extraction pass did too. The board alternates two near-greys.
const CHECKER_A := 0.6314
const CHECKER_B := 0.8431
const SAT_KEEP := 0.22   # HSV saturation above this is real art, below is board (or board showing through glow)
const LUM_TOL := 0.045    # how close to a checker tone before it's background
const SOFT := 2.0         # widen the tolerance this much for partial alpha, to soften AA edges


static func _background_alpha(c: Color) -> float:
	# 1.0 = fully keep, 0.0 = fully keyed out.
	#
	# Keys the whole grey BAND spanned by the checkerboard, not just the two
	# tones. Keying only the exact tones left two artifacts: the seam between
	# two squares is an intermediate grey (~0.74) that matched neither, leaving
	# a visible grid; and the bolt's soft glow blended with the board into
	# mid-greys, leaving a grey halo around the sprite. Anything greyish inside
	# the band is board (or board showing through glow) and goes; brighter
	# near-whites and darker tones are real art and stay.
	# HSV saturation, not max-min: the board showing through the bolt's soft
	# glow picks up a faint tint, which max-min read as "coloured art" and so
	# left a checkered grey halo around the sprite. The real art is strongly
	# saturated (cyan ice ~0.7, orange flame ~0.8), so a saturation floor
	# separates them cleanly; bright near-white highlights survive on luminance
	# below, since they sit above the checker band.
	if c.s > SAT_KEEP:
		return 1.0
	var lum: float = (c.r + c.g + c.b) / 3.0
	var lo: float = CHECKER_A - LUM_TOL
	var hi: float = CHECKER_B + LUM_TOL
	if lum >= lo and lum <= hi:
		return 0.0
	# Feather just outside the band so the cut doesn't leave a hard fringe.
	var d: float = lo - lum if lum < lo else lum - hi
	var feather: float = LUM_TOL * (SOFT - 1.0)
	if d < feather:
		return d / feather
	return 1.0


func _init() -> void:
	var sheet := Image.load_from_file(SRC)
	if sheet == null:
		printerr("could not load %s" % SRC)
		quit(1)
		return
	sheet.convert(Image.FORMAT_RGBA8)
	# Key the checkerboard out first, so the bounding-box pass below measures
	# the ARTWORK rather than the whole canvas.
	for y in sheet.get_height():
		for x in sheet.get_width():
			var c := sheet.get_pixel(x, y)
			var a := _background_alpha(c)
			if a < 1.0:
				sheet.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))
	var sw := sheet.get_width()
	var sh := sheet.get_height()
	var fw: int = sw / FRAMES
	print("sheet %dx%d -> %d frames of %dx%d" % [sw, sh, FRAMES, fw, sh])

	# Pass 1: opaque bounds of each frame, expressed in frame-local coords.
	var min_x := fw
	var min_y := sh
	var max_x := 0
	var max_y := 0
	for f in FRAMES:
		for y in sh:
			for x in fw:
				if sheet.get_pixel(f * fw + x, y).a > 0.15:  # ignore faint keyed residue so the crop hugs the real art
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		printerr("sheet appears fully transparent")
		quit(1)
		return
	min_x = maxi(min_x - PAD, 0)
	min_y = maxi(min_y - PAD, 0)
	max_x = mini(max_x + PAD, fw - 1)
	max_y = mini(max_y + PAD, sh - 1)
	var cw := max_x - min_x + 1
	var ch := max_y - min_y + 1
	print("shared crop: x=%d y=%d %dx%d (was %dx%d per frame)" % [min_x, min_y, cw, ch, fw, sh])

	# Pass 2: cut each frame out at that shared rect.
	for f in FRAMES:
		var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		out.blit_rect(sheet, Rect2i(f * fw + min_x, min_y, cw, ch), Vector2i.ZERO)
		var path := "%s%02d.png" % [OUT_PREFIX, f + 1]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		var opaque := 0
		for y in ch:
			for x in cw:
				if out.get_pixel(x, y).a > 0.02:
					opaque += 1
		print("frame %d -> %s  (%d opaque px)  %s" % [f + 1, path, opaque, "OK" if err == OK else "FAILED"])
	quit(0)
