"""Каталог звуковых эффектов для tools/gen_audio.py.

Каждый звук — функция (rng, v) -> массив float, v — номер варианта. Метаданные
(громкость в игре, разброс высоты, число голосов, приоритет) идут в
audio/catalog.json и читаются сервисом SfxService. Стиль — чиптюн + шум: узнаваемо,
мало весит, не режет слух (пик каждого звука нормирован таблицей `peak`).
"""
import numpy as np
from audio_dsp import (SR, mtof, osc, sweep, env_exp, env_ar, fft_filter, place,
                       silence, reverb_tail, crush, hold, softclip, tvec)

REG = {}


def sfx(name, peak=0.8, db=0.0, pv=0.05, prio=1, voices=3, cd=0, variants=1,
        duck=0.0, loop=False, post=None):
    def deco(fn):
        REG[name] = dict(fn=fn, peak=peak, db=db, pv=pv, prio=prio, voices=voices,
                         cd=cd, variants=variants, duck=duck, loop=loop)
        return fn
    return deco


# --------------------------------------------------------------------------
# Кирпичики
# --------------------------------------------------------------------------

def body(f0, f1, dur, decay, curve=2.0):
    n = int(dur * SR)
    return osc("sin", sweep(f0, f1, n, curve), n) * env_exp(n, SR, decay, 0.0008)


def nburst(dur, rng, lo=None, hi=None, decay=0.03, attack=0.001, order=2):
    n = int(dur * SR)
    x = fft_filter(rng.standard_normal(n), SR, lo, hi, order)
    x = x / (np.max(np.abs(x)) + 1e-9)
    return x * env_exp(n, SR, decay, attack)


def bell(f, dur, decay, partials=((1.0, 1.0),), attack=0.001):
    n = int(dur * SR)
    out = np.zeros(n)
    for ratio, amp in partials:
        fr = f * ratio
        if fr > SR * 0.45:
            continue
        out += amp * np.sin(2 * np.pi * fr * np.arange(n) / SR) * env_exp(n, SR, decay / (0.6 + 0.4 * ratio), attack)
    return out


METAL = ((1.0, 1.0), (2.76, 0.55), (5.40, 0.30), (8.93, 0.14))
GLASS = ((1.0, 1.0), (2.0, 0.45), (3.0, 0.25), (4.1, 0.12))


def chip(kind, f, dur, decay, duty=0.5, lp=6000.0, attack=0.003, vib=0.0, vib_hz=6.0):
    n = int(dur * SR)
    fr = np.full(n, float(f))
    if vib:
        fr = fr * (1.0 + vib * np.sin(2 * np.pi * vib_hz * np.arange(n) / SR))
    x = osc(kind, fr, n, SR, duty)
    if lp:
        x = fft_filter(x, SR, hi=lp, order=2)
    return x * env_exp(n, SR, decay, attack)


def mix(total, parts):
    buf = silence(total)
    for t0, sig, g in parts:
        place(buf, sig * g, int(t0 * SR))
    return buf


def grit(dur, rng, count, hi=2500.0, decay=0.004):
    """Россыпь мелких щелчков — «крошка» породы."""
    n = int(dur * SR)
    out = np.zeros(n)
    for _ in range(count):
        t0 = int(rng.random() ** 1.6 * n * 0.9)
        amp = 0.3 + 0.7 * rng.random()
        k = int(0.012 * SR)
        click = fft_filter(rng.standard_normal(k), SR, lo=500.0, hi=hi) * env_exp(k, SR, decay, 0.0003)
        place(out, click * amp, t0)
    return out


# --------------------------------------------------------------------------
# Интерфейс
# --------------------------------------------------------------------------

@sfx("ui_tap", peak=0.55, pv=0.04, voices=2, cd=25, variants=1)
def _ui_tap(rng, v):
    return mix(0.07, [(0, body(760, 520, 0.07, 0.022), 1.0),
                      (0, nburst(0.01, rng, lo=1500, hi=6000, decay=0.003), 0.35)])


@sfx("ui_open", peak=0.6, pv=0.03, voices=2, cd=60)
def _ui_open(rng, v):
    a = body(420, 640, 0.09, 0.05, 1.0)
    b = body(640, 960, 0.11, 0.06, 1.0)
    air = nburst(0.16, rng, lo=1500, hi=5000, decay=0.06, attack=0.03) * 0.25
    return mix(0.2, [(0, a, 0.8), (0.05, b, 0.9), (0, air, 1.0)])


@sfx("ui_close", peak=0.55, pv=0.03, voices=2, cd=60)
def _ui_close(rng, v):
    a = body(900, 600, 0.09, 0.05, 1.0)
    b = body(600, 400, 0.11, 0.06, 1.0)
    return mix(0.2, [(0, a, 0.8), (0.05, b, 0.9)])


@sfx("ui_tab", peak=0.5, pv=0.05, voices=2, cd=30)
def _ui_tab(rng, v):
    return mix(0.06, [(0, chip("tri", 880, 0.06, 0.02, lp=5000), 1.0),
                      (0, nburst(0.008, rng, lo=2000, hi=7000, decay=0.002), 0.3)])


@sfx("ui_toggle", peak=0.55, pv=0.03, voices=2, cd=40)
def _ui_toggle(rng, v):
    return mix(0.14, [(0, chip("sqr", 523, 0.06, 0.03, duty=0.25, lp=4500), 0.7),
                      (0.05, chip("sqr", 784, 0.09, 0.04, duty=0.25, lp=4500), 0.8)])


@sfx("ui_buy", peak=0.75, pv=0.02, prio=2, voices=2, cd=80)
def _ui_buy(rng, v):
    click = nburst(0.03, rng, lo=800, hi=4500, decay=0.008)
    a = bell(1318.5, 0.35, 0.16, GLASS)
    b = bell(1975.5, 0.45, 0.2, GLASS)
    spark = nburst(0.25, rng, lo=5000, decay=0.07, attack=0.02) * 0.25
    return reverb_tail(mix(0.5, [(0, click, 0.6), (0.01, a, 0.8), (0.07, b, 0.8), (0.07, spark, 1.0)]),
                       SR, rt60=0.25, wet=0.12)


@sfx("ui_deny", peak=0.45, pv=0.02, voices=2, cd=100)
def _ui_deny(rng, v):
    a = chip("sqr", 150, 0.1, 0.07, duty=0.5, lp=900)
    b = chip("sqr", 118, 0.13, 0.08, duty=0.5, lp=900)
    return mix(0.26, [(0, a, 0.9), (0.1, b, 1.0)])


@sfx("ui_slider", peak=0.4, pv=0.12, voices=1, cd=35)
def _ui_slider(rng, v):
    return chip("tri", 1000, 0.035, 0.011, lp=4000)


# --------------------------------------------------------------------------
# Деньги
# --------------------------------------------------------------------------

@sfx("coin", peak=0.7, pv=0.07, prio=1, voices=3, cd=45, variants=2)
def _coin(rng, v):
    f2 = 1318.5 * (1.0 if v == 0 else 1.06)
    a = chip("sqr", f2 * 0.75, 0.05, 0.05, duty=0.5, lp=5500)
    b = chip("sqr", f2, 0.3, 0.09, duty=0.5, lp=5500)
    shine = bell(f2 * 2.0, 0.2, 0.06, ((1.0, 1.0),)) * 0.25
    return mix(0.36, [(0, a, 0.7), (0.05, b, 0.85), (0.05, shine, 1.0)])


@sfx("coins_big", peak=0.8, pv=0.02, prio=2, voices=2, cd=150, duck=3.0)
def _coins_big(rng, v):
    notes = [76, 79, 83, 84, 88, 83, 91, 88, 95]
    parts = []
    for i, m in enumerate(notes):
        t0 = i * 0.055
        parts.append((t0, chip("sqr", float(mtof(m)), 0.16, 0.05, duty=0.5, lp=6500), 0.5))
        parts.append((t0, bell(float(mtof(m + 12)), 0.2, 0.05, ((1.0, 1.0),)), 0.12))
    sparkle = nburst(0.7, rng, lo=6000, decay=0.25, attack=0.04) * 0.2
    parts.append((0.0, sparkle, 1.0))
    return reverb_tail(mix(1.0, parts), SR, rt60=0.35, wet=0.12)


@sfx("sell", peak=0.8, pv=0.02, prio=2, voices=2, cd=120)
def _sell(rng, v):
    chk = nburst(0.05, rng, lo=600, hi=3500, decay=0.012)
    drawer = body(180, 90, 0.12, 0.05) * 0.8
    ring = bell(2093, 0.6, 0.28, METAL)
    ring2 = bell(2637, 0.5, 0.22, METAL)
    coins = []
    for i in range(5):
        coins.append((0.16 + i * 0.05, chip("sqr", 1568 + 120 * (i % 3), 0.07, 0.025, lp=5500), 0.28))
    return reverb_tail(mix(0.9, [(0, chk, 0.8), (0, drawer, 0.7), (0.07, ring, 0.55), (0.11, ring2, 0.4)] + coins),
                       SR, rt60=0.3, wet=0.1)


# --------------------------------------------------------------------------
# Копка: земля / камень / руда / золото / твёрдое
# --------------------------------------------------------------------------

@sfx("dig_dirt", peak=0.8, pv=0.09, prio=1, voices=3, cd=35, variants=3)
def _dig_dirt(rng, v):
    thump = body(100 + 9 * v, 52, 0.13, 0.05)
    crunch = nburst(0.15, rng, lo=140, hi=1500 + 250 * v, decay=0.04, attack=0.002)
    crumbs = grit(0.14, rng, 7, hi=2200)
    return mix(0.16, [(0, thump, 0.8), (0, crunch, 0.9), (0.01, crumbs, 0.45)])


@sfx("dig_stone", peak=0.85, pv=0.08, prio=1, voices=3, cd=35, variants=3)
def _dig_stone(rng, v):
    click = nburst(0.05, rng, lo=1500, hi=6500, decay=0.011)
    ring = bell(640 + 70 * v, 0.1, 0.035, ((1.0, 1.0), (2.4, 0.5)))
    thump = body(150, 78, 0.1, 0.04)
    chips = grit(0.12, rng, 5, hi=4500, decay=0.003)
    return mix(0.15, [(0, click, 0.9), (0, ring, 0.35), (0, thump, 0.7), (0.012, chips, 0.4)])


@sfx("dig_ore", peak=0.85, pv=0.08, prio=1, voices=3, cd=35, variants=3)
def _dig_ore(rng, v):
    crack = nburst(0.06, rng, lo=900, hi=6000, decay=0.012)
    metal = bell(480 + 60 * v, 0.28, 0.12, METAL)
    thump = body(130, 70, 0.1, 0.04)
    chips = grit(0.12, rng, 6, hi=5000, decay=0.003)
    return reverb_tail(mix(0.3, [(0, crack, 0.8), (0, metal, 0.5), (0, thump, 0.6), (0.01, chips, 0.4)]),
                       SR, rt60=0.15, wet=0.08)


@sfx("dig_gold", peak=0.85, pv=0.05, prio=2, voices=2, cd=50, variants=2)
def _dig_gold(rng, v):
    crack = nburst(0.05, rng, lo=900, hi=6000, decay=0.01)
    thump = body(140, 75, 0.09, 0.035)
    f = 1318.5 * (1.0 if v == 0 else 1.122)
    b1 = bell(f, 0.5, 0.22, GLASS)
    b2 = bell(f * 1.5, 0.55, 0.24, GLASS)
    sp = nburst(0.4, rng, lo=6000, decay=0.12, attack=0.01) * 0.2
    return reverb_tail(mix(0.65, [(0, crack, 0.7), (0, thump, 0.6), (0.02, b1, 0.55), (0.09, b2, 0.5), (0.04, sp, 1.0)]),
                       SR, rt60=0.3, wet=0.12)


@sfx("dig_hard", peak=0.9, pv=0.06, prio=2, voices=2, cd=45, variants=2)
def _dig_hard(rng, v):
    thump = body(88, 44, 0.16, 0.07)
    clank = bell(340 + 40 * v, 0.3, 0.16, METAL)
    click = nburst(0.03, rng, lo=2000, hi=8000, decay=0.006)
    return mix(0.34, [(0, thump, 0.9), (0, clank, 0.55), (0, click, 0.7)])


@sfx("tile_break", peak=0.85, pv=0.06, prio=2, voices=2, cd=80, variants=2)
def _tile_break(rng, v):
    n = int(0.5 * SR)
    rumble = fft_filter(rng.standard_normal(n), SR, lo=80, hi=700 + 200 * v) * env_exp(n, SR, 0.16, 0.004)
    pops = grit(0.5, rng, 14, hi=3500, decay=0.006)
    thump = body(95, 45, 0.18, 0.08)
    return mix(0.52, [(0, rumble, 0.9 / (np.max(np.abs(rumble)) + 1e-9)), (0, pops, 0.7), (0, thump, 0.8)])


# --------------------------------------------------------------------------
# Движение
# --------------------------------------------------------------------------

@sfx("step", peak=0.4, pv=0.1, prio=0, voices=2, cd=120, variants=4)
def _step(rng, v):
    return mix(0.09, [(0, nburst(0.08, rng, lo=100, hi=650 + 70 * v, decay=0.025, attack=0.002), 0.9),
                      (0, body(85, 52, 0.07, 0.03), 0.6)])


@sfx("step_grass", peak=0.34, pv=0.1, prio=0, voices=2, cd=120, variants=3)
def _step_grass(rng, v):
    n = int(0.1 * SR)
    sw = fft_filter(rng.standard_normal(n), SR, lo=1800, hi=5200 + 400 * v) * env_ar(n, SR, 0.012, 1.8)
    return mix(0.1, [(0, sw / (np.max(np.abs(sw)) + 1e-9), 0.8), (0, body(80, 52, 0.06, 0.025), 0.45)])


@sfx("step_stone", peak=0.4, pv=0.08, prio=0, voices=2, cd=120, variants=3)
def _step_stone(rng, v):
    return mix(0.07, [(0, nburst(0.04, rng, lo=1200, hi=5500, decay=0.009), 0.8),
                      (0, bell(900 + 90 * v, 0.05, 0.015, ((1.0, 1.0), (2.3, 0.4))), 0.35),
                      (0, body(110, 60, 0.05, 0.02), 0.5)])


@sfx("jump", peak=0.6, pv=0.06, prio=1, voices=2, cd=80)
def _jump(rng, v):
    n = int(0.13 * SR)
    s = osc("tri", sweep(290, 640, n, 1.5), n) * env_exp(n, SR, 0.09, 0.003)
    air = nburst(0.12, rng, lo=900, hi=3500, decay=0.05, attack=0.02) * 0.25
    return mix(0.14, [(0, s, 0.9), (0, air, 1.0)])


@sfx("land", peak=0.7, pv=0.1, prio=1, voices=2, cd=90, variants=2)
def _land(rng, v):
    return mix(0.16, [(0, body(115 - 10 * v, 48, 0.15, 0.06), 0.95),
                      (0, nburst(0.1, rng, lo=120, hi=1000, decay=0.03), 0.6)])


@sfx("thud", peak=0.9, pv=0.06, prio=2, voices=2, cd=80)
def _thud(rng, v):
    return mix(0.3, [(0, body(78, 34, 0.28, 0.1), 1.0),
                     (0, nburst(0.14, rng, lo=100, hi=900, decay=0.04), 0.6),
                     (0, grit(0.2, rng, 6, hi=1800), 0.3)])


@sfx("fly_start", peak=0.6, pv=0.03, prio=1, voices=1, cd=200)
def _fly_start(rng, v):
    dur = 0.5
    n = int(dur * SR)
    carrier = fft_filter(rng.standard_normal(n), SR, lo=250, hi=2600)
    rate = np.cumsum(sweep(7, 30, n, 1.0)) / SR
    am = 0.55 + 0.45 * np.sin(2 * np.pi * rate)
    grow = np.minimum(1.0, np.arange(n) / (0.35 * SR)) ** 1.5
    hum = osc("saw", sweep(70, 150, n, 1.0), n)
    hum = fft_filter(hum, SR, hi=700)
    out = (carrier / np.max(np.abs(carrier)) * am * 0.8 + hum * 0.5) * grow
    return out * np.minimum(1.0, (n - np.arange(n)) / (0.08 * SR))


@sfx("fly_stop", peak=0.5, pv=0.03, prio=1, voices=1, cd=200)
def _fly_stop(rng, v):
    n = int(0.45 * SR)
    carrier = fft_filter(rng.standard_normal(n), SR, lo=250, hi=2200)
    rate = np.cumsum(sweep(26, 5, n, 1.0)) / SR
    am = 0.5 + 0.5 * np.sin(2 * np.pi * rate)
    hum = fft_filter(osc("saw", sweep(140, 60, n, 1.0), n), SR, hi=600)
    dec = np.exp(-np.arange(n) / (0.2 * SR))
    return (carrier / np.max(np.abs(carrier)) * am * 0.7 + hum * 0.45) * dec


@sfx("fly_loop", peak=0.45, pv=0.0, prio=0, voices=1, cd=0, loop=True)
def _fly_loop(rng, v):
    # Целое число периодов модуляции и гула, фильтр циркулярный — петля без шва.
    dur = 0.6
    n = int(dur * SR)
    t = np.arange(n) / SR
    carrier = fft_filter(rng.standard_normal(n), SR, lo=250, hi=2400, circular=True)
    am = 0.6 + 0.4 * np.sin(2 * np.pi * 13 * t / dur)
    hum = fft_filter(osc("saw", round(96.0 * dur) / dur, n), SR, hi=650, circular=True)
    return carrier / np.max(np.abs(carrier)) * am * 0.8 + hum * 0.5


# --------------------------------------------------------------------------
# Герой
# --------------------------------------------------------------------------

@sfx("hurt", peak=0.85, pv=0.07, prio=3, voices=1, cd=120, variants=2)
def _hurt(rng, v):
    n = int(0.22 * SR)
    a = osc("tri", sweep(520 - 40 * v, 190, n, 1.6), n) * env_exp(n, SR, 0.12, 0.002)
    b = osc("sqr", sweep(260 - 20 * v, 100, n, 1.6), n, SR, 0.25)
    b = fft_filter(b, SR, hi=2800) * env_exp(n, SR, 0.1, 0.002)
    hit = nburst(0.08, rng, lo=300, hi=3500, decay=0.02)
    return mix(0.24, [(0, a, 0.7), (0, b, 0.5), (0, hit, 0.7), (0, body(100, 55, 0.12, 0.05), 0.5)])


@sfx("die", peak=0.85, pv=0.0, prio=4, voices=1, cd=500, duck=8.0)
def _die(rng, v):
    parts = []
    notes = [(0.0, 64, 0.2), (0.2, 60, 0.2), (0.4, 57, 0.2), (0.6, 52, 0.7)]
    for t0, m, d in notes:
        parts.append((t0, chip("tri", float(mtof(m)), d + 0.05, d * 0.7, lp=3500, vib=0.012 if d > 0.5 else 0.0), 0.8))
        parts.append((t0, chip("sqr", float(mtof(m)) * 0.5, d + 0.05, d * 0.6, duty=0.25, lp=1800), 0.3))
    n = int(0.7 * SR)
    fall = osc("tri", sweep(160, 60, n, 1.0), n) * env_exp(n, SR, 0.4, 0.01)
    parts.append((0.6, fall, 0.3))
    return reverb_tail(mix(1.4, parts), SR, rt60=0.5, wet=0.12)


@sfx("respawn", peak=0.75, pv=0.0, prio=3, voices=1, cd=400)
def _respawn(rng, v):
    parts = []
    for i, m in enumerate([57, 60, 64, 69, 72]):
        parts.append((i * 0.09, chip("tri", float(mtof(m)), 0.3, 0.12, lp=5000), 0.7))
        parts.append((i * 0.09, bell(float(mtof(m + 12)), 0.3, 0.1, GLASS), 0.18))
    return reverb_tail(mix(0.8, parts), SR, rt60=0.4, wet=0.14)


@sfx("eat", peak=0.7, pv=0.06, prio=1, voices=1, cd=150, variants=2)
def _eat(rng, v):
    parts = []
    for i in range(3):
        t0 = i * (0.12 + 0.01 * v)
        parts.append((t0, nburst(0.09, rng, lo=350, hi=2600, decay=0.025, attack=0.003), 0.85))
        parts.append((t0, grit(0.09, rng, 4, hi=3500, decay=0.004), 0.35))
        parts.append((t0, body(150, 80, 0.06, 0.025), 0.35))
    return mix(0.5, parts)


@sfx("drink", peak=0.6, pv=0.05, prio=1, voices=1, cd=150)
def _drink(rng, v):
    parts = []
    for i, t0 in enumerate([0.0, 0.14, 0.3]):
        n = int(0.12 * SR)
        g = osc("sin", sweep(260 + 30 * i, 520 + 50 * i, n, 1.0), n) * env_exp(n, SR, 0.06, 0.004)
        parts.append((t0, g, 0.8))
        parts.append((t0, nburst(0.06, rng, lo=300, hi=1500, decay=0.02), 0.25))
    return mix(0.5, parts)


@sfx("heal", peak=0.65, pv=0.02, prio=2, voices=1, cd=200)
def _heal(rng, v):
    parts = []
    for i, m in enumerate([72, 76, 79, 84, 88]):
        parts.append((i * 0.075, bell(float(mtof(m)), 0.5, 0.2, GLASS), 0.5))
        parts.append((i * 0.075, chip("tri", float(mtof(m)), 0.2, 0.08, lp=4500), 0.3))
    return reverb_tail(mix(0.9, parts), SR, rt60=0.4, wet=0.14)


@sfx("warn_low", peak=0.45, pv=0.0, prio=3, voices=1, cd=600)
def _warn_low(rng, v):
    def beep(f):
        return chip("sqr", f, 0.11, 0.2, duty=0.5, lp=2800, attack=0.01) * np.minimum(
            1.0, np.linspace(1, 0, int(0.11 * SR)) * 8)
    return mix(0.4, [(0.0, beep(740), 0.8), (0.17, beep(740), 0.8)])


# --------------------------------------------------------------------------
# Прогресс
# --------------------------------------------------------------------------

@sfx("pickup", peak=0.65, pv=0.07, prio=1, voices=3, cd=40, variants=2)
def _pickup(rng, v):
    n = int(0.1 * SR)
    f0 = 640 if v == 0 else 700
    s = osc("tri", sweep(f0, f0 * 1.62, n, 1.2), n) * env_exp(n, SR, 0.07, 0.002)
    ping = bell(f0 * 3.2, 0.12, 0.04, ((1.0, 1.0),)) * 0.18
    return mix(0.14, [(0, s, 0.9), (0.02, ping, 1.0)])


@sfx("pickup_rare", peak=0.8, pv=0.02, prio=2, voices=2, cd=100)
def _pickup_rare(rng, v):
    parts = []
    for i, m in enumerate([76, 80, 83, 88]):
        parts.append((i * 0.07, chip("tri", float(mtof(m)), 0.25, 0.1, lp=5500), 0.6))
        parts.append((i * 0.07, bell(float(mtof(m + 12)), 0.4, 0.18, GLASS), 0.2))
    parts.append((0.1, nburst(0.4, rng, lo=6000, decay=0.14, attack=0.02), 0.12))
    return reverb_tail(mix(0.7, parts), SR, rt60=0.35, wet=0.14)


@sfx("levelup", peak=0.9, pv=0.0, prio=4, voices=1, cd=800, duck=6.0)
def _levelup(rng, v):
    parts = []
    run = [(0.0, 72), (0.1, 76), (0.2, 79), (0.3, 84)]
    for t0, m in run:
        parts.append((t0, chip("sqr", float(mtof(m)), 0.16, 0.07, duty=0.25, lp=5000), 0.45))
        parts.append((t0, chip("tri", float(mtof(m)), 0.16, 0.07, lp=5000), 0.4))
    for m, g in [(72, 0.5), (76, 0.45), (79, 0.45), (84, 0.5)]:
        parts.append((0.45, chip("sqr", float(mtof(m)), 0.85, 0.5, duty=0.25, lp=4200, attack=0.01), g * 0.55))
        parts.append((0.45, bell(float(mtof(m + 12)), 0.9, 0.5, GLASS), 0.2))
    parts.append((0.45, nburst(0.8, rng, lo=5500, decay=0.3, attack=0.02), 0.14))
    return reverb_tail(mix(1.6, parts), SR, rt60=0.6, wet=0.16)


@sfx("skill_buy", peak=0.8, pv=0.02, prio=2, voices=1, cd=150)
def _skill_buy(rng, v):
    parts = []
    for i, m in enumerate([67, 70, 74, 77, 79, 82]):
        parts.append((i * 0.045, chip("sqr", float(mtof(m)), 0.1, 0.04, duty=0.25, lp=5200), 0.5))
    parts.append((0.28, bell(float(mtof(86)), 0.5, 0.25, GLASS), 0.6))
    parts.append((0.28, bell(float(mtof(91)), 0.5, 0.25, GLASS), 0.4))
    return reverb_tail(mix(0.8, parts), SR, rt60=0.3, wet=0.12)


@sfx("artifact", peak=0.85, pv=0.0, prio=4, voices=1, cd=800, duck=8.0)
def _artifact(rng, v):
    parts = []
    for t0, m in [(0.0, 62), (0.12, 69), (0.26, 74), (0.42, 78), (0.6, 81)]:
        parts.append((t0, bell(float(mtof(m)), 1.4, 0.7, GLASS), 0.55))
        parts.append((t0, bell(float(mtof(m + 12)), 1.0, 0.4, ((1.0, 1.0),)), 0.15))
    n = int(1.8 * SR)
    pad = osc("sin", 293.7, n) * 0.25 + osc("sin", 440.0, n) * 0.2
    pad *= env_ar(n, SR, 0.5, 1.5)
    parts.append((0.0, pad, 0.5))
    parts.append((0.5, nburst(1.0, rng, lo=5000, decay=0.4, attack=0.15), 0.12))
    return reverb_tail(mix(2.4, parts), SR, rt60=1.1, wet=0.28)


@sfx("quest_done", peak=0.85, pv=0.0, prio=3, voices=1, cd=500, duck=4.0)
def _quest_done(rng, v):
    parts = []
    for t0, m, d in [(0.0, 67, 0.12), (0.13, 72, 0.12), (0.26, 76, 0.5)]:
        parts.append((t0, chip("sqr", float(mtof(m)), d + 0.1, d * 0.9, duty=0.25, lp=4500, attack=0.005), 0.5))
        parts.append((t0, chip("tri", float(mtof(m)), d + 0.1, d * 0.9, lp=4500), 0.4))
    parts.append((0.26, bell(float(mtof(88)), 0.5, 0.25, GLASS), 0.25))
    return reverb_tail(mix(0.95, parts), SR, rt60=0.4, wet=0.14)


@sfx("reward", peak=0.85, pv=0.0, prio=3, voices=1, cd=400, duck=4.0)
def _reward(rng, v):
    parts = []
    for i, m in enumerate([72, 76, 79, 84, 88, 91]):
        parts.append((i * 0.06, chip("tri", float(mtof(m)), 0.2, 0.09, lp=6000), 0.45))
        parts.append((i * 0.06, bell(float(mtof(m + 12)), 0.4, 0.2, GLASS), 0.18))
    for m in (84, 88, 91):
        parts.append((0.4, bell(float(mtof(m)), 0.8, 0.4, GLASS), 0.3))
    parts.append((0.0, nburst(1.0, rng, lo=6000, decay=0.4, attack=0.1), 0.12))
    return reverb_tail(mix(1.2, parts), SR, rt60=0.5, wet=0.16)


# --------------------------------------------------------------------------
# Мир
# --------------------------------------------------------------------------

@sfx("quake", peak=0.9, pv=0.03, prio=4, voices=1, cd=1500, duck=6.0)
def _quake(rng, v):
    dur = 2.4
    n = int(dur * SR)
    t = np.arange(n) / SR
    low = fft_filter(rng.standard_normal(n), SR, lo=30, hi=180, order=3)
    low = low / np.max(np.abs(low))
    mid = fft_filter(rng.standard_normal(n), SR, lo=120, hi=600, order=2)
    mid = mid / np.max(np.abs(mid))
    wob = 0.65 + 0.35 * np.sin(2 * np.pi * 7.5 * t)
    env = np.minimum(1.0, t / 0.25) * np.exp(-np.maximum(0.0, t - 1.0) / 0.7)
    sub = osc("sin", 41.0, n) * 0.5
    out = (low * 0.9 + mid * 0.55 + sub) * wob * env
    out += grit(dur, rng, 26, hi=1800) * 0.4 * env
    return out


@sfx("collapse", peak=0.9, pv=0.04, prio=3, voices=1, cd=800, variants=2)
def _collapse(rng, v):
    dur = 1.5
    n = int(dur * SR)
    parts = []
    for i in range(22):
        t0 = (rng.random() ** 1.7) * 1.1
        dd = 0.08 + 0.12 * rng.random()
        parts.append((t0, nburst(dd, rng, lo=150, hi=1200 + 800 * rng.random(), decay=dd * 0.4), 0.4 + 0.5 * rng.random() * (1.0 - t0 / 1.6)))
    base = fft_filter(rng.standard_normal(n), SR, lo=60, hi=500) * env_exp(n, SR, 0.5, 0.01)
    parts.append((0.0, base / (np.max(np.abs(base)) + 1e-9), 0.6))
    parts.append((1.0, body(70, 34, 0.4, 0.15), 0.9))
    parts.append((1.0, nburst(0.3, rng, lo=100, hi=900, decay=0.1), 0.6))
    return mix(dur, parts)


@sfx("lava_hiss", peak=0.8, db=-2.0, pv=0.05, prio=1, voices=1, cd=600)
def _lava_hiss(rng, v):
    dur = 1.1
    n = int(dur * SR)
    hiss = fft_filter(rng.standard_normal(n), SR, lo=1800, hi=7500)
    hiss /= np.max(np.abs(hiss))
    env = env_ar(n, SR, 0.2, 1.6)
    out = hiss * env * 0.7
    out += grit(dur, rng, 18, hi=4500, decay=0.005) * 0.8
    out += fft_filter(rng.standard_normal(n), SR, lo=80, hi=400) * env * 0.25
    return out


@sfx("door", peak=0.7, pv=0.05, prio=1, voices=1, cd=200, variants=2)
def _door(rng, v):
    n = int(0.28 * SR)
    f = sweep(130, 210 - 20 * v, n, 1.0) * (1.0 + 0.03 * np.sin(2 * np.pi * 24 * np.arange(n) / SR))
    creak = osc("saw", f, n)
    creak = fft_filter(creak, SR, lo=280, hi=1500, order=2) * env_ar(n, SR, 0.03, 1.2)
    creak /= np.max(np.abs(creak)) + 1e-9
    return mix(0.5, [(0, creak, 0.55), (0.26, body(110, 55, 0.14, 0.06), 0.9),
                     (0.26, nburst(0.08, rng, lo=200, hi=1800, decay=0.02), 0.5)])


@sfx("phone", peak=0.45, pv=0.0, prio=2, voices=1, cd=600)
def _phone(rng, v):
    parts = []
    for burst_t in (0.0, 0.6):
        n = int(0.38 * SR)
        t = np.arange(n) / SR
        warble = np.where((t * 17.0) % 1.0 < 0.5, 1400.0, 1800.0)
        s = osc("sin", warble, n) + 0.3 * osc("sin", warble * 2, n)
        s = fft_filter(s, SR, hi=4000) * np.minimum(1.0, t / 0.01) * np.minimum(1.0, (0.38 - t) / 0.03)
        parts.append((burst_t, s, 0.7))
    return mix(1.0, parts)


# --------------------------------------------------------------------------
# Бой
# --------------------------------------------------------------------------

@sfx("swing", peak=0.5, pv=0.08, prio=1, voices=2, cd=60, variants=2)
def _swing(rng, v):
    n = int(0.17 * SR)
    x = rng.standard_normal(n)
    lo_band = fft_filter(x, SR, lo=300, hi=900)
    hi_band = fft_filter(x, SR, lo=1500, hi=4500)
    u = np.linspace(0, 1, n)
    out = lo_band / np.max(np.abs(lo_band)) * (1 - u) + hi_band / np.max(np.abs(hi_band)) * u
    return out * env_ar(n, SR, 0.05, 1.5)


@sfx("hit_enemy", peak=0.85, pv=0.08, prio=2, voices=2, cd=50, variants=3)
def _hit_enemy(rng, v):
    n = int(0.12 * SR)
    s = osc("sqr", sweep(330 - 30 * v, 90, n, 2.0), n)
    s = fft_filter(s, SR, hi=2500) * env_exp(n, SR, 0.05, 0.001)
    return mix(0.14, [(0, nburst(0.07, rng, lo=300, hi=3800, decay=0.02), 0.8),
                      (0, s, 0.6), (0, body(120, 60, 0.1, 0.04), 0.5)])


@sfx("enemy_die", peak=0.85, pv=0.06, prio=2, voices=2, cd=80, variants=2)
def _enemy_die(rng, v):
    n = int(0.32 * SR)
    s = osc("tri", sweep(720 - 60 * v, 120, n, 1.4), n) * env_exp(n, SR, 0.16, 0.002)
    puff = nburst(0.22, rng, lo=250, hi=3000, decay=0.07, attack=0.004)
    pop = bell(1100, 0.1, 0.03, ((1.0, 1.0),))
    return mix(0.36, [(0, s, 0.7), (0.05, puff, 0.7), (0.26, pop, 0.3)])


@sfx("boss_roar", peak=0.95, pv=0.03, prio=4, voices=1, cd=1500, duck=8.0)
def _boss_roar(rng, v):
    dur = 1.7
    n = int(dur * SR)
    t = np.arange(n) / SR
    f0 = sweep(66, 44, n, 1.0) * (1.0 + 0.04 * np.sin(2 * np.pi * 9 * t))
    core = osc("saw", f0, n)
    form = fft_filter(core, SR, lo=180, hi=900, order=2) + 0.6 * fft_filter(core, SR, lo=700, hi=1600, order=2)
    growl = 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 27 * t))
    n_part = fft_filter(rng.standard_normal(n), SR, lo=100, hi=1100) * 0.5
    env = np.minimum(1.0, t / 0.18) * np.exp(-np.maximum(0.0, t - 0.7) / 0.5)
    out = (form / (np.max(np.abs(form)) + 1e-9) + n_part) * growl * env
    out += osc("sin", f0 * 0.5, n) * 0.6 * env
    return out


@sfx("hurt_armor", peak=0.85, pv=0.06, prio=2, voices=2, cd=70, variants=2)
def _hurt_armor(rng, v):
    return mix(0.45, [(0, bell(430 + 50 * v, 0.4, 0.2, METAL), 0.7),
                      (0, nburst(0.04, rng, lo=1500, hi=7000, decay=0.008), 0.8),
                      (0, body(120, 60, 0.09, 0.035), 0.6)])
