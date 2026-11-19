extends Control
## A spacer in the bottom HUD (docs/HUD_LAYOUT.md). The panel art (assets/ui/hud_panel.png) is drawn as two halves,
## each with one plain strip that stretches, so on a window wider than the art each strip takes half the extra
## width and the crest stays centred. This spacer is its base width plus that half, which keeps the HUD's
## controls in the painted windows as the strips grow.
@export var base_width := 0.0
## The art's own width, at the HUD's scale.
@export var art_width := 1100.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(fit)
	fit()
func fit() -> void:
	custom_minimum_size.x = base_width+maxf(0.0,(get_viewport_rect().size.x-art_width)/2.0)
