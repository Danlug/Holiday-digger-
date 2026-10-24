shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;
// light_overlay.gdshader — затемнение глубиной, тёплый факел героя и ночная дымка поверхности одним
// полноэкранным прямоугольником (ветка world-fx, scripts/world/light_layer.gd). Экран не читаем (дёшево
// для gl_compatibility и телефона): выдаём премультиплицированный цвет, поэтому темнота (alpha) и тёплый
// свет (rgb поверх) считаются за один проход. Яркость квантуется ступенями с упорядоченным дизерингом по
// МИРОВЫМ пикселям, чтобы рисунок не «плыл» при движении камеры и оставался пиксель-артом.

uniform vec2 origin;            // мировая позиция левого верхнего угла прямоугольника, px
uniform vec2 hero;              // мировая позиция героя, px
uniform float torch_r = 112.0;  // радиус факела, px
uniform float torch_in = 36.0;  // внутри этого радиуса темноты нет совсем
uniform float depth_dark = 0.0; // затемнение за факелом, 0..1
uniform vec3 dark_color = vec3(0.06, 0.04, 0.03);
uniform vec3 torch_color = vec3(1.0, 0.72, 0.4);
uniform float torch_k = 0.0;    // сила тёплого света
uniform float night_k = 0.0;    // ночь на поверхности, 0..1 (уже с максимумом alpha)
uniform vec3 night_color = vec3(0.04, 0.07, 0.19);
uniform float night_up = 150.0;
uniform float night_down = 420.0;
uniform float surface_y = 32.0; // мировой y линии земли

varying vec2 wp;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float dither(vec2 q) {
	int ix = int(mod(q.x, 4.0));
	int iy = int(mod(q.y, 4.0));
	return BAYER[iy * 4 + ix] / 16.0;
}

float quant(float v, float steps, float b) {
	return clamp(floor(v * steps + b) / steps, 0.0, 1.0);
}

void vertex() {
	wp = origin + VERTEX;
}

void fragment() {
	float b = dither(floor(wp));
	float d = length(wp - hero);
	float lit = 1.0 - smoothstep(torch_in, torch_r, d);

	// Квантуем ПРОФИЛЬ (0..1), а не итоговую альфу: вдали от факела профиль равен 1 и узор не мерцает
	// шахматкой по всей стене, а у края факела идут ступени с дизерингом.
	// Подземная тьма: растёт от земли вниз (небо и кромка не темнеют), факел её вырезает.
	float under = smoothstep(surface_y, surface_y + 120.0, wp.y);
	float alpha = depth_dark * quant(under * (1.0 - 0.92 * lit), 8.0, b);
	vec3 rgb = dark_color * alpha;

	// Тёплый свет факела: аддитивная часть, только под землёй и в сумерках.
	float warm = pow(1.0 - smoothstep(0.0, torch_r * 1.05, d), 1.8);
	rgb += torch_color * torch_k * quant(warm, 8.0, b) * 0.5;

	// Ночь на поверхности: дымка у земли, с высотой и глубиной сходит на нет, факел и тут светит.
	float up = 1.0 - smoothstep(0.0, night_up, surface_y - wp.y);
	float dn = 1.0 - smoothstep(0.0, night_down, wp.y - surface_y);
	float nmask = wp.y < surface_y ? up : dn;
	float naq = night_k * quant(nmask * (1.0 - 0.8 * lit), 8.0, b);
	rgb = rgb * (1.0 - naq) + night_color * naq;
	alpha = alpha + naq * (1.0 - alpha);

	COLOR = vec4(rgb, alpha);
}
