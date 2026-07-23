extends SceneTree
## Character sprite-sheet extractor. Run:
##   godot --headless --path . --script res://scripts/tools/extract_boss_sheet.gd
##
## (2026-07-23) Separate from extract_vfx_sheet.gd because character sheets are
## structured completely differently from the VFX ones:
##   * baked-in title and per-row LABEL text, which must never become frames
##   * sprites sit on a light-grey GRID (cells + thin separator lines), the
##     whole thing over a near-black background
##   * rows hold different frame counts
##
## Strategy: find the light-grey grid BANDS (merging across the thin grid lines,
## which would otherwise split one animation row into ~4 slivers). The label
## text lives in the black gaps BETWEEN bands, so cropping to bands excludes it
## without needing to detect text at all. Within a band, crop to the grid's own
## x-extent so the black background never reaches the frame splitter -- the
## armour is very dark, so keying black would eat the character.

const SRC := "D:/WORK/PROJECT/GODOT/image/Fallen Knight.png"
const OUT_DIR := "res://art/bosses/"
# Row index (in detection order, top to bottom) -> output name. Rows not listed
# are skipped; extracting every row would emit 28 PNGs when only these are used.
const ROWS := {
	0: "fallen_knight_idle",
	1: "fallen_knight_walk",
}

const BAND_LIGHT_FRAC := 0.22   # fraction of a row that must be light grey to be grid
const BAND_MERGE_GAP := 12      # merge bands closer than this -- thin grid lines
const MIN_BAND_HEIGHT := 25
const GREY_LUM_MIN := 0.55      # light grey CELL FILL starts here (used for band/extent detection)
const GREY_SAT_MAX := 0.20      # ...and must be near-colourless
const COL_MIN_GAP := 25       # wide: a sprite has internal gaps (between legs, arm and body) of a few px that must NOT split it; real inter-frame gaps here are ~75px
const MIN_COL_PIXELS := 3       # sprite pixels needed before a column counts as occupied
const MIN_FRAME_WIDTH := 20     # narrower than this is a grid border line, not a character
const PAD := 2

# Measured off the sheet: the cell FILL is lum ~0.79 at s~0.00, while the cell
# BORDER lines are mid-greys ~0.40-0.65, also colourless. Keying only the fill
# left those borders as unbroken vertical lines, so no column was ever empty and
# a whole row came out as one frame. The character, by contrast, is either DARK
# (armour, lum < 0.30) or strongly PURPLE (s > 0.25) -- so "is this a sprite
# pixel" separates cleanly from every shade of grid, without needing to know
# each line's exact tone.
const SPRITE_SAT_MIN := 0.25
const SPRITE_LUM_MAX := 0.30


func _is_grid(c: Color) -> bool:
	var lum: float = (c.r + c.g + c.b) / 3.0
	return lum > GREY_LUM_MIN and c.s < GREY_SAT_MAX


func _is_sprite(c: Color) -> bool:
	var lum: float = (c.r + c.g + c.b) / 3.0
	return c.s > SPRITE_SAT_MIN or lum < SPRITE_LUM_MAX


func _init() -> void:
	var img := Image.load_from_file(SRC)
	if img == null:
		printerr("could not load %s" % SRC)
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("sheet %dx%d" % [w, h])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# --- 1. grid bands (label text sits in the black gaps between them)
	var raw: Array = []
	var in_band := false
	var start := 0
	for y in h:
		var light := 0
		for x in range(0, w, 3):
			if _is_grid(img.get_pixel(x, y)):
				light += 1
		var is_band: bool = float(light) / float(int(w / 3.0)) > BAND_LIGHT_FRAC
		if is_band and not in_band:
			in_band = true
			start = y
		elif not is_band and in_band:
			in_band = false
			raw.append(Vector2i(start, y - 1))
	if in_band:
		raw.append(Vector2i(start, h - 1))

	var bands: Array = []
	for r in raw:
		var band: Vector2i = r
		if not bands.is_empty() and band.x - bands[bands.size() - 1].y <= BAND_MERGE_GAP:
			bands[bands.size() - 1].y = band.y  # same animation row, split by a grid line
		else:
			bands.append(band)
	var kept: Array = []
	for b in bands:
		if b.y - b.x + 1 >= MIN_BAND_HEIGHT:
			kept.append(b)
	print("animation rows detected: %d" % kept.size())
	for i in kept.size():
		print("  row %d: y %d..%d" % [i, kept[i].x, kept[i].y])

	# --- 2. per row: crop to the grid, key the grey, split into frames
	for i in kept.size():
		if not ROWS.has(i):
			continue
		var band: Vector2i = kept[i]
		var out_name: String = ROWS[i]
		_extract_row(img, band, out_name)
	quit(0)


func _extract_row(sheet: Image, band: Vector2i, out_name: String) -> void:
	var w := sheet.get_width()
	# Grid x-extent: outside it is black background, which must be cropped
	# rather than keyed (the armour is nearly black itself).
	var x0 := w
	var x1 := 0
	for y in range(band.x, band.y + 1):
		for x in w:
			if _is_grid(sheet.get_pixel(x, y)):
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	if x1 <= x0:
		print("  %s: no grid found" % out_name)
		return

	# Copy the row out and key the grey grid to transparent.
	var rw := x1 - x0 + 1
	var rh := band.y - band.x + 1
	var row := Image.create(rw, rh, false, Image.FORMAT_RGBA8)
	row.blit_rect(sheet, Rect2i(x0, band.x, rw, rh), Vector2i.ZERO)
	# Keep only genuine sprite pixels; every shade of grid (fill AND border
	# lines) goes transparent.
	for y in rh:
		for x in rw:
			if not _is_sprite(row.get_pixel(x, y)):
				row.set_pixel(x, y, Color(0, 0, 0, 0))

	# Split into frames on empty columns.
	var used: Array = []
	used.resize(rw)
	for x in rw:
		# Counted, not "any": a few stray anti-aliased pixels along a cell border
		# would otherwise bridge two frames into one.
		var hits := 0
		for y in rh:
			if row.get_pixel(x, y).a > 0.15:
				hits += 1
		used[x] = hits >= MIN_COL_PIXELS
	var spans: Array = []
	var s := -1
	var gap := 0
	for x in rw:
		if used[x]:
			if s < 0:
				s = x
			gap = 0
		elif s >= 0:
			gap += 1
			if gap >= COL_MIN_GAP:
				spans.append(Vector2i(s, x - gap))
				s = -1
				gap = 0
	if s >= 0:
		spans.append(Vector2i(s, rw - 1))
	# The grid's CELL BORDER lines are near-black, so they pass the "dark =
	# sprite" test and survive keying as thin full-height columns -- which came
	# out as 8 sprites + 7 border lines = 15 "frames". A border is 1-3px wide and
	# a character is ~75px, so a width floor separates them cleanly.
	var real: Array = []
	for sp in spans:
		if sp.y - sp.x + 1 >= MIN_FRAME_WIDTH:
			real.append(sp)
	spans = real
	if spans.is_empty():
		print("  %s: no frames" % out_name)
		return

	# Vertical extent of the whole row, so every frame shares one height.
	var y0 := rh
	var y1 := 0
	for y in rh:
		for x in rw:
			if row.get_pixel(x, y).a > 0.15:
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
				break
	var cw := 0
	for sp in spans:
		cw = maxi(cw, sp.y - sp.x + 1)
	cw += PAD * 2
	var ch: int = (y1 - y0 + 1) + PAD * 2

	for i in spans.size():
		var sp: Vector2i = spans[i]
		var centre: int = (sp.x + sp.y) / 2
		var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		out.blit_rect(row, Rect2i(centre - cw / 2, y0 - PAD, cw, ch), Vector2i.ZERO)
		var path := "%s%s_%02d.png" % [OUT_DIR, out_name, i + 1]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		if err != OK:
			print("  FAILED %s" % path)
	print("  %s: %d frames, %dx%d each" % [out_name, spans.size(), cw, ch])
