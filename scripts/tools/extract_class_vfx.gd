extends SceneTree
## Class-skill VFX sheet extractor. Run:
##   godot --headless --path . --script res://scripts/tools/extract_class_vfx.gd
##
## (2026-07-24) Separate from extract_vfx_sheet.gd because these sheets are a
## different problem. That one keys a transparency CHECKERBOARD out of the
## background using HSV saturation; these arrive as glowing art on FLAT BLACK,
## where saturation-keying would eat the white-hot cores of every effect.
##
## Luminance is the right key here and does two jobs at once: black becomes
## transparent, and a glow's own falloff becomes a natural alpha ramp, so the
## soft edges stay soft instead of being cut to a hard silhouette. That matters
## more than usual for these -- every frame is a glow, so a hard alpha cut would
## read as a sticker rather than light.
##
## Frames are auto-detected from the empty gaps rather than a declared grid: the
## three sheets have irregular layouts (4+2, 3+2, and 2+1+2 rows), and the
## Ranger's beam frame is far wider than its neighbours, which a fixed grid
## would slice in half -- the same failure the boss sheets hit.

const SHEETS := [
	{
		"src": "D:/WORK/PROJECT/GODOT/image/skills/class-skill/Ranger (Bright Green Volley).png",
		"out": "res://art/vfx/class_ranger_",
	},
	{
		"src": "D:/WORK/PROJECT/GODOT/image/skills/class-skill/Sniper (Bright Gold Piercing Shot).png",
		"out": "res://art/vfx/class_sniper_",
	},
	{
		# This sheet has frame NUMBERS baked in under each effect ("1".."5").
		# MIN_PIXELS_LABEL raises the per-row occupancy bar so a thin line of
		# digits never registers as content -- same class of problem the boss
		# sheets' row labels caused, where the fix was to exclude them from the
		# band rather than try to detect text.
		"src": "D:/WORK/PROJECT/GODOT/image/skills/class-skill/Juggernaut (Bright Cyan Shockwave).png",
		"out": "res://art/vfx/class_juggernaut_",
		"min_pixels": 26,
	},
	{
		"src": "D:/WORK/PROJECT/GODOT/image/skills/class-skill/Trapper (Amber Lingering Zone).png",
		"out": "res://art/vfx/class_trapper_",
	},
	{
		# Declared rects, x/y/w/h -- see the "rects" note in _extract(). Read off
		# the 1024x1024 source: orb, upper chain arc, the long central bolt, the
		# impact burst, and a shorter arc.
		"src": "D:/WORK/PROJECT/GODOT/image/skills/class-skill/Elementalist (Bright Violet Chaining Bolt).png",
		"out": "res://art/vfx/class_elementalist_",
		"rects": [
			[52, 60, 280, 270],    # 01 plasma orb -- the projectile
			[396, 100, 570, 175],  # 02 chain arc
			[52, 330, 915, 330],   # 03 long branching bolt
			[40, 640, 400, 330],   # 04 impact burst
			[548, 690, 445, 250],  # 05 shorter arc
		],
	},
]

const MIN_GAP := 14        # consecutive empty rows/cols before calling it a frame boundary
const MIN_SPAN := 40       # anything thinner than this is noise, not a frame
const KEEP_LUM := 0.055    # below this the pixel is background black
const FULL_LUM := 0.34     # at or above this the pixel is fully opaque
const OCCUPIED_ALPHA := 0.30  # alpha needed before a pixel counts toward frame detection
const MIN_PIXELS := 3      # occupied pixels in a row/col before it counts as content
const PAD := 6


func _init() -> void:
	for cfg in SHEETS:
		_extract(cfg)
	quit(0)


func _extract(cfg: Dictionary) -> void:
	var img := Image.load_from_file(cfg["src"])
	if img == null:
		printerr("could not load %s" % cfg["src"])
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("=== %s (%dx%d) ===" % [cfg["src"].get_file(), w, h])

	# Luminance -> alpha. RGB is preserved so the colour stays exactly as drawn;
	# only opacity is derived, which is what keeps the glow reading as light.
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var lum: float = maxf(maxf(c.r, c.g), c.b)
			var a: float = clampf((lum - KEEP_LUM) / maxf(FULL_LUM - KEEP_LUM, 0.001), 0.0, 1.0)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))

	# Explicit rects for sheets whose art OVERLAPS across the layout, where gap
	# detection can never find a clean boundary -- the Elementalist's central
	# bolt spans nearly the full width and reaches into the rows above and
	# below, so the whole sheet came out as a single frame. Same declared-layout
	# fallback the boss extractor needed for the Demon Beast.
	var frames: Array = []
	if cfg.has("rects"):
		for r in cfg["rects"]:
			frames.append({"x0": r[0], "x1": r[0] + r[2] - 1, "y0": r[1], "y1": r[1] + r[3] - 1, "row": frames.size()})
	else:
		var min_px: int = int(cfg.get("min_pixels", MIN_PIXELS))
		var bands := _spans(_row_occupancy(img, min_px), MIN_GAP, MIN_SPAN)
		for bi in bands.size():
			# Trim the band to its own DENSE rows before cutting. Raising the
			# occupancy threshold alone wasn't enough for the Juggernaut sheet's
			# baked-in frame numerals: the digits stayed out of band DETECTION
			# but the band still spanned them, so a faint "3" was blitted into
			# the frame. A digit row carries a tiny fraction of the pixels an
			# effect row does, so trimming by density excludes them without
			# needing to know the label's size or position.
			var band := _trim_band(img, bands[bi])
			for col in _spans(_col_occupancy(img, band, min_px), MIN_GAP, MIN_SPAN):
				frames.append({"x0": col.x, "x1": col.y, "y0": band.x, "y1": band.y, "row": bi})
	if frames.is_empty():
		print("  no frames detected")
		return

	# Frame size is shared PER ROW, not across the whole sheet. These sheets mix
	# an animation strip with standalone one-off effects, and sizing everything
	# to the sheet's widest frame made each narrow cut swallow its neighbours --
	# the Ranger's 4 bow frames (~300px) were being cut at 668px because a beam
	# on the row below is that wide, so every frame showed three bows. Per row
	# keeps an animation's frames consistent with each other (no jitter) without
	# letting an unrelated row dictate their size.
	var row_size: Dictionary = {}
	for f in frames:
		var r: int = f["row"]
		var prev: Vector2i = row_size.get(r, Vector2i.ZERO)
		row_size[r] = Vector2i(
			maxi(prev.x, f["x1"] - f["x0"] + 1),
			maxi(prev.y, f["y1"] - f["y0"] + 1),
		)
	for i in frames.size():
		var f: Dictionary = frames[i]
		var size: Vector2i = row_size[f["row"]]
		var cw: int = size.x + PAD * 2
		var ch: int = size.y + PAD * 2
		var cx: int = (f["x0"] + f["x1"]) / 2
		var cy: int = (f["y0"] + f["y1"]) / 2
		var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		out.blit_rect(img, Rect2i(cx - cw / 2, cy - ch / 2, cw, ch), Vector2i.ZERO)
		var path: String = "%s%02d.png" % [cfg["out"], i + 1]
		if out.save_png(ProjectSettings.globalize_path(path)) != OK:
			printerr("  failed to write %s" % path)
			continue
		print("  %s  %dx%d  (source %dx%d at %d,%d, row %d)" % [
			path.get_file(), cw, ch, f["x1"] - f["x0"] + 1, f["y1"] - f["y0"] + 1, f["x0"], f["y0"], f["row"],
		])
	print("  %d frames" % frames.size())


const BAND_DENSITY_KEEP := 0.15  # a row must carry this share of the band's peak to count as art


func _trim_band(img: Image, band: Vector2i) -> Vector2i:
	var counts: Array[int] = []
	var peak := 0
	for y in range(band.x, band.y + 1):
		var n := 0
		for x in img.get_width():
			if img.get_pixel(x, y).a >= OCCUPIED_ALPHA:
				n += 1
		counts.append(n)
		peak = maxi(peak, n)
	if peak <= 0:
		return band
	var floor_count: int = int(float(peak) * BAND_DENSITY_KEEP)
	var first := 0
	while first < counts.size() and counts[first] < floor_count:
		first += 1
	var last: int = counts.size() - 1
	while last > first and counts[last] < floor_count:
		last -= 1
	return Vector2i(band.x + first, band.x + last)


func _row_occupancy(img: Image, min_pixels: int) -> Array:
	var used: Array = []
	used.resize(img.get_height())
	for y in img.get_height():
		var n := 0
		for x in img.get_width():
			if img.get_pixel(x, y).a >= OCCUPIED_ALPHA:
				n += 1
		used[y] = n >= min_pixels
	return used


func _col_occupancy(img: Image, band: Vector2i, min_pixels: int) -> Array:
	var used: Array = []
	used.resize(img.get_width())
	for x in img.get_width():
		var n := 0
		for y in range(band.x, band.y + 1):
			if img.get_pixel(x, y).a >= OCCUPIED_ALPHA:
				n += 1
		used[x] = n >= min_pixels
	return used


func _spans(used: Array, min_gap: int, min_len: int) -> Array:
	var out: Array = []
	var s := -1
	var gap := 0
	for i in used.size():
		if used[i]:
			if s < 0:
				s = i
			gap = 0
		elif s >= 0:
			gap += 1
			if gap >= min_gap:
				if (i - gap) - s + 1 >= min_len:
					out.append(Vector2i(s, i - gap))
				s = -1
				gap = 0
	if s >= 0 and used.size() - s >= min_len:
		out.append(Vector2i(s, used.size() - 1))
	return out
