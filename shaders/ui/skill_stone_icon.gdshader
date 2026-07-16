shader_type canvas_item;

// 把技能石 icon 裁成圆形 + 加黑边，做成"道具币"样式。
// 三段：圆心内显示 icon 原图 → inner..radius 之间是黑边 → radius 之外 AA 渐隐为透明。
// 只运行时 mask，不动 skill_XX.png 原图（升级奖励弹窗共用同一套图标）。

uniform float radius = 0.42;           // 圆半径（UV 空间），0.5 = 内切圆贴方框边
uniform float border_width = 0.03;    // 黑边宽度（UV 空间）
uniform vec4 border_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float edge_aa = 0.01;         // 抗锯齿（UV 空间）

void fragment() {
	float d = length(UV - 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inner = radius - border_width;

	// 圆外边抗锯齿：radius 之外渐隐
	float outer_a = 1.0 - smoothstep(radius - edge_aa, radius + edge_aa, d);
	// inner 处 icon ↔ 黑边 混合（避免锯齿）
	float t = smoothstep(inner - edge_aa, inner + edge_aa, d);

	vec3 rgb = mix(c.rgb, border_color.rgb, t);
	float a = mix(c.a, 1.0, t);     // 黑边段强制不透明
	a *= outer_a;                   // 圆外统一透明

	COLOR = vec4(rgb, a);
}
