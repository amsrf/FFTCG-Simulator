extends SubViewport

# Representative rules-box colours sampled across the bundled Opus I character art.
const PANEL_COLORS := {
	"氷": [Color("#094e68"), Color("#368fae"), Color("#59b8db"), Color("#368fae"), Color("#07516c")],
	"風": [Color("#0e4b29"), Color("#228656"), Color("#309660"), Color("#228656"), Color("#0e502c")],
	"土": [Color("#67550c"), Color("#ae8b14"), Color("#d5ad18"), Color("#ae8b14"), Color("#67570b")],
	"雷": [Color("#482644"), Color("#805374"), Color("#9b678e"), Color("#805374"), Color("#4d2a4b")],
	"水": [Color("#243c5a"), Color("#587aa0"), Color("#8097b6"), Color("#587aa0"), Color("#28415f")],
	"光": [Color("#525454"), Color("#866762"), Color("#a97e73"), Color("#866762"), Color("#565354")],
	"闇": [Color("#251f1c"), Color("#595051"), Color("#858687"), Color("#595051"), Color("#201a18")],
}

func configure(artwork: Texture2D, element: String, wording: String) -> void:
	$Artwork.texture = artwork
	if PANEL_COLORS.has(element):
		var panel_texture: GradientTexture2D = $Panel.texture.duplicate()
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0, 0.25, 0.5, 0.75, 1])
		gradient.colors = PackedColorArray(PANEL_COLORS[element])
		panel_texture.gradient = gradient
		$Panel.texture = panel_texture

	wording = wording.replace("[[br]]", "\n").replace("[[ex]]EX BURST[[/]]", "").replace("[[ex]]EX BURST [[/]]", "").strip_edges()
	for tag in ["[[i]]", "[[s]]", "[[/]]", "[[ex]]"]:
		wording = wording.replace(tag, "")
	var label: Label = $Ability
	label.text = wording.replace(". ", ".\n") if wording.length() <= 60 else wording
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	while font_size > 10 and font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label.size.x, font_size).y > label.size.y - 12:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
