shader_type canvas_item;
// «Жар в воздухе»: лёгкое дрожание картинки по горизонтали, тёплый оттенок и
// красноватая виньетка. Один полноэкранный проход; узел с этим шейдером
// прячется, пока strength == 0 (scripts/tech/tech_system.gd), чтобы на холодных
// глубинах не платить за копию экрана (важно для веба и слабых телефонов).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	// две волны разной частоты: дрожание не выглядит синусоидой
	float wave = sin(uv.y * 70.0 + TIME * 3.2) * 0.6 + sin(uv.y * 31.0 - TIME * 2.3) * 0.4;
	uv.x += wave * 0.0042 * strength;
	vec3 c = texture(screen_tex, uv).rgb;
	// тёплый тон поверх картинки
	c = mix(c, c * vec3(1.18, 0.94, 0.78), 0.35 * strength);
	// красноватое марево по краям экрана
	float vig = smoothstep(0.30, 0.95, distance(SCREEN_UV, vec2(0.5)));
	c += vec3(0.55, 0.16, 0.02) * vig * 0.30 * strength;
	COLOR = vec4(c, 1.0);
}
