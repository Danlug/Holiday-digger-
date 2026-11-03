"""Звуки копки для tools/gen_audio.py (раунд 6, зона dig-sound).

Схема id (их читает scripts/fx/dig_sound.gd):
  dig_<материал>_<инструмент>  — один удар по породе; материал: dirt peat stone
                                  ore gold gem hard; инструмент: shovel pick drill
                                  (лопата берёт только dirt/peat/ore — металлолом);
  dig_lava                      — удар по лаве (любым инструментом);
  break_<материал>              — клетка разрушилась (осыпание), плюс break_lava;
  rattle                        — дребезг ржавой кирки, играется поверх удара;
  drill_loop / rig_loop         — петли моторов ручного бура и бурмобиля.

Каждый удар собран из трёх слоёв: транзиент инструмента (цок кирки, шорх лопаты,
дробь бура под нагрузкой), тело материала (глухой тумп земли, звон камня,
металлический призвук руды, стеклянный «динь» самоцветов, низ твёрдой породы)
и крошка. Варианты (3 на удар, 2 на осыпание) отличаются сидом шума, высотой
тела и раскладкой крошки — плюс разброс высоты в каталоге (pv).
"""
import numpy as np
from audio_dsp import SR, osc, sweep, env_exp, env_ar, fft_filter, place, silence, reverb_tail
from audio_sfx import sfx, body, nburst, bell, mix, grit, METAL, GLASS

MATERIALS = ("dirt", "peat", "stone", "ore", "gold", "gem", "hard")
SHOVEL_MATERIALS = ("dirt", "peat", "ore")
TOOLS = ("shovel", "pick", "drill")


# --------------------------------------------------------------------------
# Кирпичики: инструмент
# --------------------------------------------------------------------------

def pick_tick(rng, v):
    """«Цок» кирки: очень короткий щелчок с тональным «тик»."""
    click = nburst(0.03, rng, lo=1400, hi=6500, decay=0.0035, attack=0.0003)
    tik = bell(3100 + 180 * v, 0.03, 0.006, ((1.0, 1.0), (1.7, 0.4)), attack=0.0003)
    return mix(0.04, [(0, click, 1.0), (0, tik, 0.5)])


def shovel_scrape(rng, v, dur=0.11):
    """«Шорх» лопаты: шум, полоса которого съезжает вниз, пока лезвие входит в грунт."""
    n = int(dur * SR)
    x = rng.standard_normal(n)
    hi_band = fft_filter(x, SR, lo=1200, hi=4800 - 300 * v)
    lo_band = fft_filter(x, SR, lo=500, hi=2200)
    u = np.linspace(0.0, 1.0, n)
    out = hi_band / (np.max(np.abs(hi_band)) + 1e-9) * (1.0 - u) + lo_band / (np.max(np.abs(lo_band)) + 1e-9) * u
    env = env_ar(n, SR, 0.02, 1.6)
    return out * env


def drill_grind(rng, v, dur=0.09, f0=96.0):
    """Дробь бура под нагрузкой: пила мотора проседает по высоте, поверх — шум,
    промодулированный оборотами (зубья грызут породу)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    load = f0 * (1.0 - 0.14 * np.sin(np.pi * np.minimum(1.0, t / dur)) ** 2)
    motor = fft_filter(osc("saw", load, n), SR, lo=80, hi=1800, order=2)
    motor /= np.max(np.abs(motor)) + 1e-9
    chatter = fft_filter(rng.standard_normal(n), SR, lo=700, hi=4200 + 300 * v)
    chatter /= np.max(np.abs(chatter)) + 1e-9
    am = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * (f0 * 1.5) * t))
    env = env_ar(n, SR, 0.008, 1.4)
    return (motor * 0.55 + chatter * am * 0.6) * env


# --------------------------------------------------------------------------
# Кирпичики: тело материала (общее для ударов и осыпания)
# --------------------------------------------------------------------------

def mat_body(mat, rng, v, hard_hit=1.0):
    """Тело удара по материалу: (список слоёв для mix, длительность)."""
    if mat == "dirt":
        # глухо, но с серединой: низ 50–100 Гц на динамике телефона не слышен,
        # «землю» несёт хруст 150–1800 Гц
        thump = body(138 + 10 * v, 64, 0.13, 0.045)
        crunch = nburst(0.13, rng, lo=150, hi=1800 + 250 * v, decay=0.03, attack=0.002)
        crumbs = grit(0.12, rng, 7, hi=2200)
        return [(0, thump, 0.7), (0, crunch, 1.0), (0.01, crumbs, 0.4)], 0.17
    if mat == "peat":
        # сухое крошение: без низа, много крошки, полый «тук» в середине
        hollow = body(190 + 15 * v, 120, 0.07, 0.025)
        dry = nburst(0.11, rng, lo=450, hi=2800 + 300 * v, decay=0.03, attack=0.001)
        crumbs = grit(0.14, rng, 13, hi=3800, decay=0.0035)
        return [(0, hollow, 0.5), (0, dry, 0.75), (0.004, crumbs, 0.7)], 0.17
    if mat == "stone":
        click = nburst(0.05, rng, lo=1500, hi=6800, decay=0.01)
        ring = bell(700 + 90 * v, 0.14, 0.045, ((1.0, 1.0), (2.4, 0.5), (3.9, 0.2)))
        thump = body(150, 76, 0.1, 0.04)
        chips = grit(0.12, rng, 5, hi=4800, decay=0.003)
        return [(0, click, 0.9), (0, ring, 0.45), (0, thump, 0.65), (0.01, chips, 0.4)], 0.18
    if mat == "ore":
        crack = nburst(0.06, rng, lo=900, hi=6000, decay=0.012)
        metal = bell(520 + 70 * v, 0.3, 0.13, METAL)
        thump = body(130, 68, 0.1, 0.04)
        chips = grit(0.12, rng, 6, hi=5000, decay=0.003)
        return [(0, crack, 0.8), (0, metal, 0.55), (0, thump, 0.6), (0.01, chips, 0.4)], 0.32
    if mat == "gold":
        crack = nburst(0.05, rng, lo=900, hi=6000, decay=0.01)
        thump = body(140, 72, 0.09, 0.035)
        f = 1318.5 * (1.0, 1.122, 1.26)[v % 3]
        b1 = bell(f, 0.5, 0.22, GLASS)
        b2 = bell(f * 1.5, 0.55, 0.24, GLASS)
        sp = nburst(0.4, rng, lo=6000, decay=0.12, attack=0.01) * 0.2
        return [(0, crack, 0.7), (0, thump, 0.6), (0.02, b1, 0.55), (0.09, b2, 0.5), (0.04, sp, 1.0)], 0.62
    if mat == "gem":
        # самоцвет: лёгкий щелчок и очень высокий стеклянный «динь» с мерцанием
        click = nburst(0.04, rng, lo=1800, hi=8000, decay=0.007)
        f = 2093.0 * (1.0, 1.19, 1.5)[v % 3]
        b1 = bell(f, 0.5, 0.2, GLASS)
        b2 = bell(f * 1.26, 0.55, 0.24, ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1)))
        b3 = bell(f * 2.0, 0.35, 0.12, ((1.0, 1.0),))
        shimmer = nburst(0.45, rng, lo=6500, decay=0.14, attack=0.02) * 0.3
        rock = bell(900 + 60 * v, 0.1, 0.03, ((1.0, 1.0), (2.4, 0.4)))
        thump = body(190, 95, 0.06, 0.025)
        return [(0, click, 1.0), (0, thump, 0.4), (0, rock, 0.35), (0.01, b1, 0.42), (0.03, b2, 0.3), (0.05, b3, 0.22), (0.02, shimmer, 0.8)], 0.62
    if mat == "hard":
        # тяжело, с низом: суб-удар, лязг, низкий гул
        sub = body(70, 30, 0.22, 0.09 * hard_hit)
        clank = bell(330 + 45 * v, 0.32, 0.17, METAL)
        click = nburst(0.03, rng, lo=2000, hi=8000, decay=0.006)
        rumble = nburst(0.25, rng, lo=50, hi=320, decay=0.08, attack=0.003, order=3)
        chips = grit(0.14, rng, 5, hi=4200, decay=0.003)
        return [(0, sub, 1.0), (0, clank, 0.5), (0, click, 0.7), (0, rumble, 0.6), (0.012, chips, 0.3)], 0.4
    raise ValueError(mat)


def strike(mat, tool, rng, v):
    parts, dur = mat_body(mat, rng, v)
    if tool == "pick":
        # цок перед телом; у звонких материалов тело само даёт транзиент — цок тише
        g = 0.55 if mat in ("stone", "gem", "hard") else 0.85
        parts = [(0, pick_tick(rng, v), g)] + [(t0 + 0.004, s, a) for t0, s, a in parts]
        return mix(dur + 0.01, parts)
    if tool == "shovel":
        # шорх, потом лезвие упирается: тело материала приходит с задержкой и мягче
        sc = shovel_scrape(rng, v, dur=0.14)
        soft = 0.55 if mat == "dirt" else 0.7
        parts = [(0, sc, 1.4)] + [(t0 + 0.07, s, a * soft) for t0, s, a in parts]
        return mix(dur + 0.08, parts)
    if tool == "drill":
        gr = drill_grind(rng, v)
        parts = [(0, gr, 0.75)] + [(t0 + 0.01, s, a * 0.8) for t0, s, a in parts]
        return mix(dur + 0.02, parts)
    raise ValueError(tool)


def finish_strike(mat, x):
    """Самоцветам, золоту и твёрдому — короткий хвост комнаты."""
    if mat in ("gold", "gem"):
        return reverb_tail(x, SR, rt60=0.3, wet=0.12)
    if mat == "hard":
        return reverb_tail(x, SR, rt60=0.35, wet=0.1)
    if mat == "ore":
        return reverb_tail(x, SR, rt60=0.15, wet=0.08)
    return x


def _register_strikes():
    for mat in MATERIALS:
        for tool in TOOLS:
            if tool == "shovel" and mat not in SHOVEL_MATERIALS:
                continue
            name = "dig_%s_%s" % (mat, tool)
            prio = 2 if mat in ("gold", "gem", "hard") else 1
            peak = {"dirt": 0.78, "peat": 0.74, "stone": 0.84, "ore": 0.84, "gold": 0.84, "gem": 0.8, "hard": 0.9}[mat]

            def fn(rng, v, mat=mat, tool=tool):
                return finish_strike(mat, strike(mat, tool, rng, v))
            sfx(name, peak=peak, pv=0.08, prio=prio, voices=2, cd=45, variants=3)(fn)


_register_strikes()


@sfx("dig_lava", peak=0.75, pv=0.06, prio=1, voices=2, cd=60, variants=2)
def _dig_lava(rng, v):
    # шипение с «булем»: кирка входит в расплав, брызги пузырятся
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    hiss = fft_filter(rng.standard_normal(n), SR, lo=1800, hi=7500)
    hiss /= np.max(np.abs(hiss)) + 1e-9
    bubbles = 0.6 + 0.4 * np.sin(2 * np.pi * (23 + 6 * v) * t + 2.0 * np.sin(2 * np.pi * 5 * t))
    hiss *= bubbles * env_ar(n, SR, 0.015, 1.3)
    bloop = body(340 - 40 * v, 120, 0.12, 0.05, 1.5)
    pops = grit(0.25, rng, 7, hi=3000, decay=0.004)
    return mix(0.3, [(0, hiss, 0.7), (0.02, bloop, 0.6), (0.03, pops, 0.35)])


# --------------------------------------------------------------------------
# Осыпание клетки
# --------------------------------------------------------------------------

def tumble(rng, count, f_lo, f_hi, dur, decay, partials, spread=0.3):
    """Несколько обломков, падающих друг за другом, всё тише."""
    n = int(dur * SR)
    out = np.zeros(n)
    for i in range(count):
        t0 = int((0.02 + spread * (rng.random() ** 1.3)) * SR)
        f = f_lo + (f_hi - f_lo) * rng.random()
        amp = (0.4 + 0.6 * rng.random()) * (1.0 - 0.6 * t0 / max(n, 1))
        place(out, bell(f, decay * 4, decay, partials) * amp, t0)
    return out


def _break_common(rng, v, lo, hi, decay, thump_f, thump_decay, gain=0.9):
    n = int(0.5 * SR)
    rumble = fft_filter(rng.standard_normal(n), SR, lo=lo, hi=hi) * env_exp(n, SR, decay, 0.004)
    rumble /= np.max(np.abs(rumble)) + 1e-9
    thump = body(thump_f, thump_f * 0.45, 0.2, thump_decay)
    return [(0, rumble, gain), (0, thump, 0.85)]


@sfx("break_dirt", peak=0.8, pv=0.06, prio=2, voices=2, cd=60, variants=2)
def _break_dirt(rng, v):
    parts = _break_common(rng, v, 80, 650 + 150 * v, 0.14, 92, 0.07, gain=0.8)
    parts.append((0.0, grit(0.4, rng, 11, hi=2300, decay=0.005), 0.5))
    soft = nburst(0.3, rng, lo=200, hi=1200, decay=0.09, attack=0.02)
    parts.append((0.03, soft, 0.35))
    return mix(0.45, parts)


@sfx("break_peat", peak=0.74, pv=0.06, prio=2, voices=2, cd=60, variants=2)
def _break_peat(rng, v):
    # сухое крошение: шуршащая осыпь без низа
    parts = [(0, grit(0.38, rng, 34, hi=3800 + 300 * v, decay=0.004), 0.85)]
    dry = nburst(0.32, rng, lo=500, hi=3200, decay=0.08, attack=0.005)
    parts.append((0.0, dry, 0.7))
    parts.append((0, body(170, 95, 0.1, 0.04), 0.35))
    return mix(0.48, parts)


@sfx("break_stone", peak=0.86, pv=0.06, prio=2, voices=2, cd=80, variants=2)
def _break_stone(rng, v):
    parts = _break_common(rng, v, 80, 700 + 200 * v, 0.16, 95, 0.08)
    parts.append((0, grit(0.5, rng, 14, hi=3500, decay=0.006), 0.6))
    parts.append((0.02, tumble(rng, 5, 480, 950, 0.5, 0.03, ((1.0, 1.0), (2.4, 0.4))), 0.45))
    return mix(0.52, parts)


@sfx("break_ore", peak=0.86, pv=0.06, prio=2, voices=2, cd=80, variants=2)
def _break_ore(rng, v):
    parts = _break_common(rng, v, 80, 600 + 150 * v, 0.14, 100, 0.07)
    parts.append((0, grit(0.4, rng, 10, hi=4000, decay=0.004), 0.5))
    parts.append((0.02, tumble(rng, 4, 560, 1100, 0.5, 0.07, METAL), 0.5))
    return reverb_tail(mix(0.55, parts), SR, rt60=0.18, wet=0.08)


@sfx("break_gold", peak=0.86, pv=0.04, prio=2, voices=2, cd=100, variants=2)
def _break_gold(rng, v):
    parts = _break_common(rng, v, 90, 500, 0.12, 105, 0.06, gain=0.7)
    parts.append((0.02, tumble(rng, 4, 1318, 2100, 0.55, 0.12, GLASS, spread=0.32), 0.3))
    parts.append((0.03, nburst(0.45, rng, lo=6000, decay=0.14, attack=0.02), 0.22))
    return reverb_tail(mix(0.6, parts), SR, rt60=0.3, wet=0.12)


@sfx("break_gem", peak=0.84, pv=0.04, prio=2, voices=2, cd=100, variants=2)
def _break_gem(rng, v):
    # хрустальный рассып: высокие стеклянные осколки и мерцание, низа почти нет
    parts = [(0, body(160, 80, 0.1, 0.04), 0.5)]
    parts.append((0, nburst(0.05, rng, lo=2000, hi=9000, decay=0.009), 1.0))
    parts.append((0, grit(0.3, rng, 10, hi=6000, decay=0.003), 0.4))
    parts.append((0.01, tumble(rng, 6, 2093, 3900 + 300 * v, 0.6, 0.11, GLASS, spread=0.35), 0.32))
    parts.append((0.02, nburst(0.5, rng, lo=6500, decay=0.18, attack=0.02), 0.3))
    return reverb_tail(mix(0.65, parts), SR, rt60=0.4, wet=0.14)


@sfx("break_hard", peak=0.9, pv=0.04, prio=2, voices=2, cd=100, variants=2)
def _break_hard(rng, v):
    parts = _break_common(rng, v, 40, 420 + 80 * v, 0.22, 64, 0.13)
    parts.append((0, body(52, 26, 0.35, 0.16), 0.9))
    parts.append((0, grit(0.55, rng, 12, hi=3000, decay=0.006), 0.5))
    parts.append((0.03, tumble(rng, 4, 300, 620, 0.6, 0.06, METAL, spread=0.3), 0.45))
    return reverb_tail(mix(0.7, parts), SR, rt60=0.4, wet=0.12)


@sfx("break_lava", peak=0.78, pv=0.04, prio=2, voices=1, cd=150)
def _break_lava(rng, v):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    hiss = fft_filter(rng.standard_normal(n), SR, lo=1500, hi=7000)
    hiss /= np.max(np.abs(hiss)) + 1e-9
    hiss *= (0.6 + 0.4 * np.sin(2 * np.pi * 19 * t)) * env_exp(n, SR, 0.22, 0.01)
    parts = [(0, hiss, 0.7), (0.0, body(260, 90, 0.2, 0.08, 1.5), 0.6)]
    for i in range(4):
        parts.append((0.05 + 0.11 * i, body(420 - 50 * i, 180, 0.08, 0.03, 1.5), 0.3))
    return mix(0.62, parts)


# --------------------------------------------------------------------------
# Ржавая кирка и моторы
# --------------------------------------------------------------------------

@sfx("rattle", peak=0.6, pv=0.08, prio=1, voices=1, cd=60, variants=2)
def _rattle(rng, v):
    # дребезг: разболтанная насадка — три-четыре металлических щелчка и зуд
    parts = []
    t0 = 0.004
    for i in range(3 + v):
        f = 1700 + 350 * rng.random() + 200 * i
        parts.append((t0, bell(f, 0.06, 0.012, METAL, attack=0.0005), 0.6 - 0.1 * i))
        t0 += 0.016 + 0.014 * rng.random()
    n = int(0.08 * SR)
    buzz = osc("sqr", 58.0 + 6 * v, n) * fft_filter(rng.standard_normal(n), SR, lo=900, hi=3500)
    buzz = buzz / (np.max(np.abs(buzz)) + 1e-9) * env_exp(n, SR, 0.03, 0.002)
    parts.append((0.0, buzz, 0.45))
    return mix(0.14, parts)


@sfx("drill_loop", peak=0.5, db=-6.0, pv=0.0, prio=0, voices=1, cd=0, loop=True)
def _drill_loop(rng, v):
    # Ручной бур: визг мотора и дробь зубьев. Целое число периодов на длине петли,
    # фильтры циркулярные — без шва.
    dur = 0.5
    n = int(dur * SR)
    t = np.arange(n) / SR
    f_m = round(138.0 * dur) / dur
    motor = osc("saw", f_m, n) + 0.5 * osc("sin", f_m * 2.0, n) + 0.25 * osc("sin", f_m * 3.01, n)
    motor = fft_filter(motor, SR, lo=90, hi=2600, order=2, circular=True)
    motor /= np.max(np.abs(motor)) + 1e-9
    whine = fft_filter(rng.standard_normal(n), SR, lo=1800, hi=5200, circular=True)
    whine /= np.max(np.abs(whine)) + 1e-9
    f_c = round(46.0 * dur) / dur
    chatter = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f_c * t))
    wobble = 1.0 + 0.06 * np.sin(2 * np.pi * (round(3.0 * dur) / dur) * t)
    return (motor * 0.7 + whine * chatter * 0.35) * wobble


@sfx("rig_loop", peak=0.5, db=-8.0, pv=0.0, prio=0, voices=1, cd=0, loop=True)
def _rig_loop(rng, v):
    # Бурмобиль: дизель — гармоники низкого основного тона, выхлопные «пуфы» в такт,
    # лёгкий лязг цепи. Высоту меняет сервис (pitch_scale) при нагрузке.
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = round(30.0 * dur) / dur
    eng = np.zeros(n)
    for k in range(1, 11):
        eng += (1.0 / k ** 0.8) * osc("sqr" if k % 2 else "saw", f0 * k, n)
    eng = fft_filter(eng, SR, lo=40, hi=1400, order=2, circular=True)
    eng /= np.max(np.abs(eng)) + 1e-9
    puff_env = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * f0 * t))) ** 3
    puffs = fft_filter(rng.standard_normal(n), SR, lo=300, hi=2500, circular=True)
    puffs /= np.max(np.abs(puffs)) + 1e-9
    clank = fft_filter(rng.standard_normal(n), SR, lo=2500, hi=6000, circular=True)
    clank /= np.max(np.abs(clank)) + 1e-9
    clank_env = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * (f0 / 3.0) * t + 1.0))) ** 6
    return eng * 0.75 + puffs * puff_env * 0.35 + clank * clank_env * 0.12
