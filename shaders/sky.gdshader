shader_type canvas_item;
// sky.gdshader — всё небо одним непрозрачным прямоугольником (scripts/world/sky_view.gd): градиент от
// горизонта к зениту, тёплая полоса зари, свечение солнца и луны, Млечный Путь и три слоя звёзд.
// Рисуется в мировых координатах: wpos — локальная точка узла SkyView (клетки мира, y<0 — над землёй).
//
// Звёзды лежат в трёх тайлах (art/env/sky/stars_*.png, tools/gen_sky.py), где тексель — ДАННЫЕ:
// R яркость, G фаза мерцания, B цветовая температура. Тайлы повторяются без швов, у каждого свой параллакс
// (доля движения камеры, доходящая до слоя), поэтому при полёте вверх дальние звёзды отстают от ближних.
// Мерцание считается здесь же из фазы текселя: звёзды не в унисон, без таймеров и спрайтов на звезду.

uniform sampler2D stars_far : repeat_enable, filter_nearest;
uniform sampler2D stars_mid : repeat_enable, filter_nearest;
uniform sampler2D stars_near : repeat_enable, filter_nearest;
uniform sampler2D milkyway : repeat_enable, filter_linear;

// Мировой размер тайлов в логических px — те же числа, что в tools/gen_sky.py (FAR_TILE/MID_TILE/NEAR_TILE).
const vec2 FAR_TILE = vec2(384.0, 512.0);
const vec2 MID_TILE = vec2(320.0, 448.0);
const vec2 NEAR_TILE = vec2(288.0, 384.0);

uniform vec2 cam_px = vec2(0.0);                  // камера в мировых px
uniform vec3 parallax = vec3(0.45, 0.62, 0.80);   // far, mid, near: доля движения камеры, доходящая до слоя

uniform float body_shift = 0.0;                   // дрейф светил при ходьбе (экранные px по x)
uniform float horizon_y = 0.0;                    // Y кромки земли
uniform float grad_len = 130.0;                   // масштаб градиента по высоте, px
uniform vec3 col_horizon = vec3(0.5, 0.83, 0.96);
uniform vec3 col_mid = vec3(0.5, 0.83, 0.96);
uniform vec3 col_zenith = vec3(0.5, 0.83, 0.96);

uniform float twilight = 0.0;                     // 0..1 сила тёплой полосы зари
uniform vec3 tw_col_low = vec3(1.0, 0.5, 0.2);
uniform vec3 tw_col_high = vec3(0.8, 0.3, 0.5);
uniform float tw_x = 0.0;                         // где полоса ярче всего (x на экране)
uniform float tw_spread = 220.0;

uniform vec4 sun_glow = vec4(0.0, 0.0, 80.0, 0.0);   // xy экранные px, z радиус, w сила
uniform vec3 sun_col = vec3(1.0, 0.85, 0.55);
uniform vec4 moon_glow = vec4(0.0, 0.0, 30.0, 0.0);
uniform vec3 moon_col = vec3(0.62, 0.72, 1.0);

uniform float star_vis = 0.0;                     // 0 днём .. 1 глубокой ночью
uniform float neb_vis = 0.0;
uniform float twinkle = 1.0;                      // 1 обычное мерцание; меньше — тише (Settings.reduce_motion)
uniform vec2 extinction = vec2(14.0, 150.0);      // высота над горизонтом, где звёзды набирают яркость

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

vec3 temp_color(float t) {
	const vec3 a = vec3(0.60, 0.76, 1.00);
	const vec3 b = vec3(0.86, 0.92, 1.00);
	const vec3 c = vec3(1.00, 0.98, 0.94);
	const vec3 d = vec3(1.00, 0.86, 0.55);
	const vec3 e = vec3(1.00, 0.55, 0.38);
	if (t < 0.25) {
		return mix(a, b, t / 0.25);
	}
	if (t < 0.5) {
		return mix(b, c, (t - 0.25) / 0.25);
	}
	if (t < 0.75) {
		return mix(c, d, (t - 0.5) / 0.25);
	}
	return mix(d, e, (t - 0.75) / 0.25);
}

// Один слой звёзд поверх цвета неба. dim — доля, на которую гасят звёзды (горизонт, свет луны).
vec3 star_layer(vec3 col, sampler2D tex, vec2 tile, float par, float depth, float speed, float dim) {
	vec3 s = texture(tex, (wpos - (1.0 - par) * cam_px) / tile).rgb;
	if (s.r <= 0.0) {
		return col;
	}
	// Звёзды проявляются по одной: яркие первыми, тусклые к полной темноте.
	float a = s.r * smoothstep(0.0, 1.0, star_vis * 1.7 - 0.7 * (1.0 - s.r));
	float ph = s.g * 18.84956;
	float spd = mix(0.45, 1.15, fract(s.g * 37.0 + s.b * 11.0)) * speed;
	float w = 0.62 * sin(TIME * spd + ph) + 0.38 * sin(TIME * spd * 1.73 + ph * 2.1 + 1.3);
	a *= 1.0 - twinkle * depth * (0.5 - 0.5 * w);
	a *= dim;
	vec3 sc = temp_color(s.b);
	sc = mix(sc, vec3(1.0), smoothstep(0.55, 1.0, s.r) * 0.55);
	return mix(col, sc, clamp(a, 0.0, 1.0));
}

void fragment() {
	// Светила и заря прибиты к экрану (как сами спрайты солнца и луны), поэтому считаются в его координатах.
	vec2 sp = wpos - cam_px;
	float alt = max(horizon_y - wpos.y, 0.0);
	float u = 1.0 - exp(-alt / grad_len);
	vec3 col = mix(col_horizon, col_mid, smoothstep(0.0, 0.55, u));
	col = mix(col, col_zenith, smoothstep(0.45, 1.0, u));

	if (twilight > 0.0) {
		float hv = exp(-alt / 175.0);
		float dx = (sp.x - tw_x) / tw_spread;
		float side = exp(-dx * dx);
		vec3 tc = mix(tw_col_low, tw_col_high, smoothstep(0.0, 1.0, alt / 300.0));
		col = mix(col, tc, clamp(twilight * hv * mix(0.35, 1.0, side), 0.0, 0.92));
	}

	float moon_dim = 0.0;
	if (moon_glow.w > 0.0) {
		float md = distance(sp - vec2(body_shift, 0.0), moon_glow.xy);
		float r = moon_glow.z;
		col += moon_col * moon_glow.w * (0.85 * exp(-md * md / (r * r)) + 0.30 * exp(-md / (r * 2.4)));
		moon_dim = moon_glow.w * smoothstep(r * 3.2, r * 0.5, md);
	}
	if (sun_glow.w > 0.0) {
		float sd = distance(sp - vec2(body_shift, 0.0), sun_glow.xy);
		float r = sun_glow.z;
		col += sun_col * sun_glow.w * (0.70 * exp(-sd * sd / (r * r)) + 0.30 * exp(-sd / (r * 1.7)));
	}

	if (star_vis > 0.002) {
		float ext = smoothstep(extinction.x, extinction.y, alt);
		float dim = ext * (1.0 - 0.9 * clamp(moon_dim, 0.0, 1.0));
		if (neb_vis > 0.002) {
			vec3 nb = texture(milkyway, (wpos - (1.0 - parallax.x) * cam_px) / FAR_TILE).rgb;
			col += nb * neb_vis * ext * (1.0 - 0.8 * clamp(moon_dim, 0.0, 1.0));
		}
		col = star_layer(col, stars_far, FAR_TILE, parallax.x, 0.30, 0.8, dim);
		col = star_layer(col, stars_mid, MID_TILE, parallax.y, 0.50, 1.0, dim);
		col = star_layer(col, stars_near, NEAR_TILE, parallax.z, 0.62, 1.2, dim);
	}

	col += (ign(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(col, 1.0);
}
