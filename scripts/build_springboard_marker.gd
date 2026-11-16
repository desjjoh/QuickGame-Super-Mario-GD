extends SceneTree

const PREVIEW := preload("res://scripts/marker_preview.gd")


func _initialize() -> void:
	var spring := PREVIEW.texture_image(preload("res://assets/items/spring.png"))
	var check_only := "--check" in OS.get_cmdline_user_args()
	for theme: String in PREVIEW.THEME_NAMES:
		var atlas := load(
			"res://assets/palettes/" + theme + "/tileset/Palette 1 (Ground and Stone).png"
		) as Texture2D
		var image := Image.create(16, 32, false, Image.FORMAT_RGBA8)
		image.blit_rect(PREVIEW.texture_image(atlas), Rect2i(16, 8, 16, 8), Vector2i(0, 24))
		image.blend_rect(spring, Rect2i(0, 8, 16, 24), Vector2i(0, 1))
		if not PREVIEW.save_preview(image, PREVIEW.output_path(theme, "springboard"), check_only):
			quit(1)
			return
	print("Springboard marker previews: PASS")
	quit()
