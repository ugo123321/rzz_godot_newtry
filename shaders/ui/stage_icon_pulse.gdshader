shader_type canvas_item;

uniform float scale_factor : hint_range(0.5, 1.5, 0.001) = 1.0;

void fragment() {
	vec2 uv = (UV - vec2(0.5)) / scale_factor + vec2(0.5);
	// scale_factor < 1 时 UV 会超出 [0,1]，默认采样会夹取/重复边缘像素，阴影会多出一块。
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0);
	} else {
		COLOR = texture(TEXTURE, uv);
	}
}
