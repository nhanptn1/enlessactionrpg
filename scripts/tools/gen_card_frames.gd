extends SceneTree
## One-off asset generator. Run:
##   godot --headless --path . --script res://scripts/tools/gen_card_frames.gd
##
## (2026-07-23) The wave-clear card frames were ONE greyscale base texture
## recoloured per element with a StyleBoxTexture multiply-tint. Multiply can
## only ever darken toward a single hue, which is why Lightning could never get
## its authored purple+yellow TWO-TONE look (entry 69 flagged this as needing
## custom art). It doesn't: a duotone remap gets there from the same base.
##
## For every pixel we keep the base's alpha (so the ornate cut-out shape is
## preserved exactly) and map its luminance across a dark->light colour ramp.
## Shadows take the dark tone, highlights take the light tone -- so Lightning
## reads as deep purple in the recesses and bright yellow on the raised edges,
## which is exactly the two-tone that a flat multiply could not produce.
## Every other line keeps the hue the user already approved; they just gain
## depth instead of being one flat wash.

const BASE := "res://art/ui/card_frame_base.png"
const OUT_DIR := "res://art/ui/"

# element -> [shadow colour, highlight colour]
const RAMPS := {
	"physical": [Color(0.04, 0.20, 0.06), Color(0.58, 1.00, 0.52)],
	"fire": [Color(0.30, 0.03, 0.02), Color(1.00, 0.76, 0.26)],
	"frost": [Color(0.03, 0.12, 0.32), Color(0.76, 0.96, 1.00)],
	"lightning": [Color(0.20, 0.04, 0.38), Color(1.00, 0.92, 0.35)],  # the two-tone: purple shadow -> yellow highlight
	"class": [Color(0.28, 0.15, 0.02), Color(1.00, 0.88, 0.45)],
}


func _init() -> void:
	var base := Image.load_from_file(ProjectSettings.globalize_path(BASE))
	if base == null:
		printerr("could not load %s" % BASE)
		quit(1)
		return
	base.convert(Image.FORMAT_RGBA8)
	var w := base.get_width()
	var h := base.get_height()
	print("base %dx%d" % [w, h])

	for element in RAMPS:
		var shadow: Color = RAMPS[element][0]
		var light: Color = RAMPS[element][1]
		var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var px := base.get_pixel(x, y)
				if px.a <= 0.0:
					out.set_pixel(x, y, Color(0, 0, 0, 0))
					continue
				# The base is greyscale, so any channel is the luminance; use the
				# proper weighting anyway so this stays correct if the base is
				# ever replaced with real coloured art.
				var l: float = clampf(px.r * 0.299 + px.g * 0.587 + px.b * 0.114, 0.0, 1.0)
				var c := shadow.lerp(light, l)
				out.set_pixel(x, y, Color(c.r, c.g, c.b, px.a))
		var path := "%scard_frame_duo_%s.png" % [OUT_DIR, element]
		var err := out.save_png(ProjectSettings.globalize_path(path))
		print("%s -> %s" % [element, "OK" if err == OK else "FAILED (%d)" % err])
	quit(0)
