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

# (2026-07-23) Frames are now AUTO-DETECTED from the transparent gaps between
# sprites rather than assuming a uniform cols x rows grid. The third sheet
# (fire_lightning.png) proved the grid assumption wrong: its final explosion
# frame is drawn much larger than the others and straddles a cell boundary, so
# a fixed grid sliced it into two half-explosions. Gap detection also removes
# the need to declare cols/rows/count per sheet at all.
const SHEETS := [
	{
		"src": "D:/WORK/PROJECT/GODOT/image/skills/fire_lightning.png",
		"out": "res://art/vfx/overload_burst_",
	},
]

const MIN_GAP := 12  # consecutive empty rows/cols needed to call it a frame boundary

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

	var boxes := _find_frames(sheet)
	if boxes.is_empty():
		printerr("  no frames detected")
		return
	print("  sheet %dx%d -> %d frames detected" % [sheet.get_width(), sheet.get_height(), boxes.size()])

	# One common frame size (the largest detected box + pad), with each frame
	# CENTRED on its own content. Frames differ in size here -- the explosion is
	# far bigger than the opening beam -- so centring is what keeps the
	# animation from lurching around as it plays.
	var cw := 0
	var ch := 0
	for b in boxes:
		cw = maxi(cw, int(b.size.x))
		ch = maxi(ch, int(b.size.y))
	cw += PAD * 2
	ch += PAD * 2
	print("  common frame size: %dx%d" % [cw, ch])

	for i in boxes.size():
		var b: Rect2i = boxes[i]
		var centre := b.position + b.size / 2
		var src_rect := Rect2i(centre.x - cw / 2, centre.y - ch / 2, cw, ch)
		var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		out.blit_rect(sheet, src_rect, Vector2i.ZERO)
		var path := "%s%02d.png" % [out_prefix, i + 1]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		var opaque := 0
		for y in ch:
			for x in cw:
				if out.get_pixel(x, y).a > 0.02:
					opaque += 1
		print("  frame %d %s -> %s (%d opaque px) %s" % [i + 1, b, path, opaque, "OK" if err == OK else "FAILED"])


func _spans(occupied: Array) -> Array:
	# Contiguous runs of `true`, merged across gaps shorter than MIN_GAP so a
	# sprite's own internal transparency never splits it into two frames.
	var spans: Array = []
	var start := -1
	var gap := 0
	for i in occupied.size():
		if occupied[i]:
			if start < 0:
				start = i
			gap = 0
		elif start >= 0:
			gap += 1
			if gap >= MIN_GAP:
				spans.append(Vector2i(start, i - gap))
				start = -1
				gap = 0
	if start >= 0:
		spans.append(Vector2i(start, occupied.size() - 1))
	return spans


func _find_frames(img: Image) -> Array:
	# Rows of content first, then columns within each row band -- so a sheet
	# laid out as a strip, a grid, or a ragged mix all segment correctly.
	var w := img.get_width()
	var h := img.get_height()
	var row_used: Array = []
	row_used.resize(h)
	for y in h:
		var any := false
		for x in w:
			if img.get_pixel(x, y).a > BBOX_ALPHA:
				any = true
				break
		row_used[y] = any
	var frames: Array = []
	for b in _spans(row_used):
		var band: Vector2i = b
		var col_used: Array = []
		col_used.resize(w)
		for x in w:
			var any := false
			for y in range(band.x, band.y + 1):
				if img.get_pixel(x, y).a > BBOX_ALPHA:
					any = true
					break
			col_used[x] = any
		for c2 in _spans(col_used):
			var col: Vector2i = c2
			# Tighten vertically to this frame's own content, since a band's
			# extent is the union of everything sharing that row.
			var y0: int = band.y
			var y1: int = band.x
			for y in range(band.x, band.y + 1):
				for x in range(col.x, col.y + 1):
					if img.get_pixel(x, y).a > BBOX_ALPHA:
						y0 = mini(y0, y)
						y1 = maxi(y1, y)
						break
			frames.append(Rect2i(col.x, y0, col.y - col.x + 1, y1 - y0 + 1))
	return frames
