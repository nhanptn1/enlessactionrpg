extends SceneTree
## Generates art/ui/icons/icon_chain_arrow.png -- the physical line's Chain
## Arrow icon. Run:
##   godot --headless --path . --script res://scripts/tools/gen_chain_arrow_icon.gd
##
## (2026-07-24) Chain Arrow and Chain Shot were reusing icon_chain_spark.png,
## which is LIGHTNING's tier-2 icon: a violet bolt in a purple ring. Two
## different skill lines were showing the same art in the same picker, and the
## physical one was wearing the wrong element's colour. Per user: "clean its
## colour and back to raw physical colour".
##
## Rather than hand-pick a palette, the ramp is SAMPLED from the physical line's
## own icon_piercing_arrow.png, so Chain Arrow matches whatever that art
## actually uses (dark navy ring, silver-white content) instead of a guess that
## drifts if the physical look is ever revisited. Luminance drives the remap and
## the source alpha is preserved untouched, which keeps the chain-spark
## silhouette exactly as drawn -- the same duotone technique gen_card_frames.gd
## uses for the card frames.

const SOURCE := "res://art/ui/icons/icon_chain_spark.png"
const PALETTE_REF := "res://art/ui/icons/icon_piercing_arrow.png"
const OUT := "res://art/ui/icons/icon_chain_arrow.png"
const ALPHA_CUTOFF := 0.25


func _init() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	var ref := Image.load_from_file(ProjectSettings.globalize_path(PALETTE_REF))
	if src == null or ref == null:
		printerr("could not load source or palette reference")
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)
	ref.convert(Image.FORMAT_RGBA8)

	# Sample the reference's darkest and lightest opaque tones -- the two ends of
	# the physical palette. Percentile-based rather than absolute min/max so a
	# stray anti-aliased pixel can't define the whole ramp.
	var lums: Array[float] = []
	var by_lum: Dictionary = {}
	for y in ref.get_height():
		for x in ref.get_width():
			var c := ref.get_pixel(x, y)
			if c.a < ALPHA_CUTOFF:
				continue
			var l: float = (c.r + c.g + c.b) / 3.0
			lums.append(l)
			by_lum[l] = c
	if lums.is_empty():
		printerr("palette reference had no opaque pixels")
		quit(1)
		return
	lums.sort()
	var dark: Color = by_lum[lums[int(lums.size() * 0.08)]]
	var light: Color = by_lum[lums[int(lums.size() * 0.96)]]
	print("physical palette sampled: dark=%s light=%s" % [dark, light])

	# Remap the source's luminance across that ramp, alpha untouched.
	var out := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	var min_l := 1.0
	var max_l := 0.0
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a < 0.01:
				continue
			var l: float = (c.r + c.g + c.b) / 3.0
			min_l = minf(min_l, l)
			max_l = maxf(max_l, l)
	var span: float = maxf(max_l - min_l, 0.001)
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a < 0.01:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var l: float = ((c.r + c.g + c.b) / 3.0 - min_l) / span
			var mapped := dark.lerp(light, clampf(l, 0.0, 1.0))
			mapped.a = c.a
			out.set_pixel(x, y, mapped)
	var err := out.save_png(ProjectSettings.globalize_path(OUT))
	if err != OK:
		printerr("failed to write %s" % OUT)
		quit(1)
		return
	print("wrote %s (%dx%d)" % [OUT, out.get_width(), out.get_height()])
	quit(0)
