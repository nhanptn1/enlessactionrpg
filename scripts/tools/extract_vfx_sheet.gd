extends SceneTree
## Generic VFX sheet extractor. Configure SHEETS below and run:
##   godot --headless --path . --script res://scripts/tools/extract_vfx_sheet.gd
##
## (2026-07-23) Generalised from extract_frostfire.gd once a second sheet
## arrived that broke both of that version's assumptions: frost_lightning.png
## is a 2x2 GRID rather than a horizontal strip, and its checkerboard is DARK
## where fire_frost.png's was light. So layout is now per-sheet config and the
## board tones are auto-detected from the border instead of hardcoded.
##
## The source sheets ship with the transparency checkerboard baked in as real
## opaque pixels, so it must be keyed out (already-extracted assets in art/vfx
## are ~89% transparent). Keying rules, both learned the hard way on the first
## sheet -- see _background_alpha().
##
## Every frame of a sheet is cropped to ONE shared rect (the union of all
## frames' opaque bounds) so the animation cannot jitter or change scale.

const SHEETS := [
	{
		"src": "D:/WORK/PROJECT/GODOT/image/skills/frost_lightning.png",
		"out": "res://art/vfx/superconductor_arc_",
		"cols": 2,
		"rows": 2,
	},
]

const PAD := 4          # breathing room so edge glow isn't clipped
const SAT_KEEP := 0.22  # HSV saturation above this is real art, below is board
const LUM_TOL := 0.045  # how far outside the detected board band still counts as board
const SOFT := 2.0       # widen tolerance this much for partial alpha, softening AA edges
const BBOX_ALPHA := 0.15  # ignore faint keyed residue so the crop hugs the real art

var _lo := 0.0
var _hi := 0.0


func _background_alpha(c: Color) -> float:
	# 1.0 = keep, 0.0 = key out.
	#
	# Two artifacts drove this design on the first sheet: keying only the two
	# exact checker tones left the SEAM between squares (an intermediate grey)
	# as a visible grid, so the whole grey BAND is keyed; and using max-min to
	# detect "grey" left a checkered halo where the sprite's soft glow blended
	# with the board, so HSV saturation is the discriminator instead. Bright
	# near-white highlights survive because they sit outside the band.
	if c.s > SAT_KEEP:
		return 1.0
	var lum: float = (c.r + c.g + c.b) / 3.0
	if lum >= _lo and lum <= _hi:
		return 0.0
	var d: float = _lo - lum if lum < _lo else lum - _hi
	var feather: float = LUM_TOL * (SOFT - 1.0)
	if d < feather:
		return d / feather
	return 1.0


func _detect_board(img: Image) -> void:
	# The outermost ring is always board, so read the tones from there rather
	# than hardcoding -- sheets arrive with both light and dark checkerboards.
	var w := img.get_width()
	var h := img.get_height()
	var lo := 1.0
	var hi := 0.0
	for x in range(0, w, 2):
		for y in [0, 1, 2, h - 3, h - 2, h - 1]:
			var c := img.get_pixel(x, y)
			if c.s > SAT_KEEP:
				continue
			var l: float = (c.r + c.g + c.b) / 3.0
			lo = minf(lo, l)
			hi = maxf(hi, l)
	_lo = lo - LUM_TOL
	_hi = hi + LUM_TOL
	print("  detected board tones: %.4f .. %.4f (keying %.4f .. %.4f)" % [lo, hi, _lo, _hi])


func _init() -> void:
	for sheet_cfg in SHEETS:
		_extract(sheet_cfg)
	quit(0)


func _extract(cfg: Dictionary) -> void:
	var src: String = cfg["src"]
	var out_prefix: String = cfg["out"]
	var cols: int = cfg["cols"]
	var rows: int = cfg["rows"]
	print("=== %s ===" % src)
	var sheet := Image.load_from_file(src)
	if sheet == null:
		printerr("  could not load")
		return
	sheet.convert(Image.FORMAT_RGBA8)
	_detect_board(sheet)

	for y in sheet.get_height():
		for x in sheet.get_width():
			var c := sheet.get_pixel(x, y)
			var a := _background_alpha(c)
			if a < 1.0:
				sheet.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * a))

	var fw: int = sheet.get_width() / cols
	var fh: int = sheet.get_height() / rows
	var count := cols * rows
	print("  sheet %dx%d -> %d frames of %dx%d" % [sheet.get_width(), sheet.get_height(), count, fw, fh])

	# Union bounds across every frame, in frame-local coords.
	var min_x := fw
	var min_y := fh
	var max_x := 0
	var max_y := 0
	for i in count:
		var ox: int = (i % cols) * fw
		var oy: int = (i / cols) * fh
		for y in fh:
			for x in fw:
				if sheet.get_pixel(ox + x, oy + y).a > BBOX_ALPHA:
					min_x = mini(min_x, x)
					max_x = maxi(max_x, x)
					min_y = mini(min_y, y)
					max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		printerr("  sheet appears fully transparent after keying")
		return
	min_x = maxi(min_x - PAD, 0)
	min_y = maxi(min_y - PAD, 0)
	max_x = mini(max_x + PAD, fw - 1)
	max_y = mini(max_y + PAD, fh - 1)
	var cw := max_x - min_x + 1
	var ch := max_y - min_y + 1
	print("  shared crop: x=%d y=%d %dx%d" % [min_x, min_y, cw, ch])

	# Frames are read in natural order: left-to-right, then top-to-bottom.
	for i in count:
		var ox: int = (i % cols) * fw
		var oy: int = (i / cols) * fh
		var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		out.blit_rect(sheet, Rect2i(ox + min_x, oy + min_y, cw, ch), Vector2i.ZERO)
		var path := "%s%02d.png" % [out_prefix, i + 1]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		var opaque := 0
		for y in ch:
			for x in cw:
				if out.get_pixel(x, y).a > 0.02:
					opaque += 1
		print("  frame %d -> %s (%d opaque px) %s" % [i + 1, path, opaque, "OK" if err == OK else "FAILED"])
