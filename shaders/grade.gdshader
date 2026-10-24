shader_type canvas_item;
// grade.gdshader — общая цветокоррекция дня/ночи для фоновых подложек
// (scripts/world/backdrop.gd). Контракт с автозагрузкой DayCycle
// (scripts/core/day_cycle.gd, делает другой агент): она отдаёт
// { "exposure": float, "saturation": float, "contrast": float } через
// метод grade(), 1.0 везде — день без изменений. Этот шейдер только читает
// три числа как uniform'ы и ничего не знает про то, кто их посчитал — если
// автозагрузки ещё нет (или задачи дня/ночи ещё нет в сборке), значения по
// умолчанию (1.0/1.0/1.0) оставляют картинку как есть.

uniform float exposure : hint_range(0.0, 2.0) = 1.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float gray = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(gray), c.rgb, saturation);
	c.rgb = (c.rgb - 0.5) * contrast + 0.5;
	c.rgb *= exposure;
	c.rgb = clamp(c.rgb, 0.0, 1.0);
	COLOR = c;
}
