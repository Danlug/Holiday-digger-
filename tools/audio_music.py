"""Музыка для tools/gen_audio.py: семь зацикленных дорожек.

Каждая дорожка — циркулярный буфер ровно в целое число тактов: хвосты нот и
реверберация заворачиваются через границу (place_wrap, reverb_circ, фильтры
без дополнения), поэтому конец петли плавно переходит в начало без шва.
Гармония — диатоника (мажор/натуральный минор) с опорой сильных долей на
аккордовые звуки; тембры мягкие (аддитивные щипки, марими́ба, стеклянные колокола,
FM-электропиано, пэды), басы синусные, ударные приглушены; мастеринг — ФНЧ и мягкий
ограничитель, острых пиков нет.
"""
import numpy as np
from audio_dsp import (MSR, mtof, fft_filter, place_wrap, reverb_send, echo_circ,
                       rng_for)

SR = MSR

TRACKS = {
    "mus_surface": dict(bpm=92, bars=24, db=-2.0, quality=3),
    "mus_mine_1": dict(bpm=78, bars=24, db=-2.0, quality=3),
    "mus_mine_2": dict(bpm=66, bars=20, db=-2.0, quality=3),
    "mus_deep": dict(bpm=50, bars=16, db=-1.0, quality=3),
    "mus_boss": dict(bpm=132, bars=28, db=-3.0, quality=3),
    "mus_story": dict(bpm=72, bars=20, db=-2.0, quality=3),
    "mus_shop": dict(bpm=108, bars=24, db=-3.0, quality=3),
}
# Меню и магазин — одна дорожка: короткая, добрая, не раздражающая.
ALIASES = {"mus_menu": "mus_shop"}


# --------------------------------------------------------------------------
# Сетка и теория
# --------------------------------------------------------------------------

def smooth_len(n):
    """Ближайшая длина с малыми простыми множителями — быстрый FFT."""
    def ok(k):
        for p in (2, 3, 5, 7):
            while k % p == 0:
                k //= p
        return k == 1
    for d in range(0, int(n * 0.01) + 2):
        for cand in (n + d, n - d):
            if ok(cand):
                return cand
    return n


class Grid:
    def __init__(self, bpm, bars):
        self.bars = bars
        n = int(round(bars * 4 * 60.0 / bpm * SR))
        self.n = smooth_len(n)
        self.step = self.n / (bars * 16.0)   # отсчётов на шестнадцатую

    def pos(self, bar, step16=0.0):
        return int(round((bar * 16 + step16) * self.step))

    def sec(self, steps16):
        return steps16 * self.step / SR


class Mix:
    def __init__(self, name, bpm, bars):
        self.name = name
        self.g = Grid(bpm, bars)
        self.rng = rng_for(name)
        self.buses = {}
        self.n = self.g.n

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros(self.n)
        return self.buses[name]

    def add(self, bus, sig, bar, step16=0.0, gain=1.0, jitter=0.0):
        off = 0.0
        if jitter:
            off = (self.rng.random() - 0.5) * 2 * jitter * SR
        place_wrap(self.bus(bus), sig * gain, self.g.pos(bar, step16) + int(off))


MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]

CHORDS = {
    "maj": [0, 4, 7], "min": [0, 3, 7], "sus2": [0, 2, 7], "maj7": [0, 4, 7, 11],
    "min7": [0, 3, 7, 10], "min9": [0, 3, 7, 14], "pw": [0, 7, 12], "dom": [0, 4, 7, 10],
}


def chord_pcs(root, kind):
    return [(root + i) % 12 for i in CHORDS[kind]]


def voicing_candidates(root, kind, lo=53, hi=76):
    pcs = chord_pcs(root, kind)
    notes = [m for m in range(lo - 12, hi + 13) if m % 12 in pcs]
    cands = []
    for base in range(lo, lo + 12):
        v = []
        for pc in pcs:
            m = base + ((pc - base) % 12)
            v.append(m)
        v = sorted(v)
        if v[-1] <= hi:
            cands.append(v)
    return cands or [sorted(notes)[:len(pcs)]]


def lead_voicings(prog, lo=53, hi=76):
    """Плавное ведение голосов пэда: из кандидатов выбираем ближайший к предыдущему."""
    out = []
    prev = None
    for root, kind in prog:
        cands = voicing_candidates(root, kind, lo, hi)
        if prev is None:
            best = min(cands, key=lambda v: abs(np.mean(v) - 64))
        else:
            best = min(cands, key=lambda v: sum(abs(a - b) for a, b in zip(sorted(v)[:len(prev)], prev[:len(v)]))
                       + 0.3 * abs(len(v) - len(prev)))
        out.append(best)
        prev = best
    return out


def bass_note(root, octave_base=36):
    return octave_base + ((root - octave_base) % 12)


def scale_list(root, intervals, lo, hi):
    pcs = {(root + i) % 12 for i in intervals}
    return [m for m in range(lo, hi + 1) if m % 12 in pcs]


# --------------------------------------------------------------------------
# Инструменты (возвращают массив длиной с хвостом)
# --------------------------------------------------------------------------

def _t(n):
    return np.arange(n) / SR


def rel_gate(n, hold_n, rel_s=0.06):
    g = np.ones(n)
    r = max(1, int(rel_s * SR))
    end = min(n, hold_n + r)
    if hold_n < n:
        g[hold_n:end] = np.linspace(1.0, 0.0, end - hold_n)
        g[end:] = 0.0
    return g


def i_pluck(f, dur, bright=0.58, tau=0.9, rel=0.12):
    n = int((dur + rel + 0.05) * SR)
    t = _t(n)
    out = np.zeros(n)
    for k in range(1, 14):
        fk = f * k
        if fk > SR * 0.42:
            break
        a = k ** -1.15 * bright ** (k - 1)
        out += a * np.sin(2 * np.pi * fk * t) * np.exp(-t / (tau / (1 + 0.85 * (k - 1))))
    att = np.minimum(1.0, t / 0.004)
    return out * att * rel_gate(n, int(dur * SR), rel)


def i_marimba(f, dur, tau=0.45):
    n = int((dur + 0.15) * SR)
    t = _t(n)
    out = np.sin(2 * np.pi * f * t) * np.exp(-t / tau)
    out += 0.30 * np.sin(2 * np.pi * f * 3.97 * t) * np.exp(-t / (tau * 0.22))
    out += 0.08 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / (tau * 0.08))
    return out * np.minimum(1.0, t / 0.002) * rel_gate(n, int(dur * SR), 0.1)


def i_glass(f, dur, tau=1.4):
    n = int((dur + 0.3) * SR)
    t = _t(n)
    out = np.zeros(n)
    for ratio, amp, d in [(1.0, 1.0, 1.0), (2.01, 0.4, 0.6), (2.99, 0.2, 0.4), (4.2, 0.1, 0.25)]:
        if f * ratio < SR * 0.42:
            out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / (tau * d))
    return out * np.minimum(1.0, t / 0.003)


def i_epiano(f, dur, tau=1.3):
    n = int((dur + 0.3) * SR)
    t = _t(n)
    idx = 1.6 * np.exp(-t / 0.5) + 0.25
    car = np.sin(2 * np.pi * f * t + idx * np.sin(2 * np.pi * f * t))
    tine = 0.05 * np.sin(2 * np.pi * f * 14 * t + 0.4 * np.sin(2 * np.pi * f * 14 * t)) * np.exp(-t / 0.06) if f * 14 < SR * 0.42 else 0.0
    out = (car * np.exp(-t / tau) + tine)
    return out * np.minimum(1.0, t / 0.004) * rel_gate(n, int(dur * SR), 0.18)


def i_pad(f, dur, attack=0.5, rel=0.8, harm=6, detunes=(-6.0, 0.0, 6.0), warmth=0.72, drift=0.0):
    n = int((dur + rel) * SR)
    t = _t(n)
    out = np.zeros(n)
    for ci, c in enumerate(detunes):
        fc = f * 2 ** (c / 1200.0)
        ph0 = ci * 1.3
        for k in range(1, harm + 1):
            if fc * k > SR * 0.4:
                break
            out += (warmth ** (k - 1) / k) * np.sin(2 * np.pi * fc * k * t + ph0 * k)
    if drift:
        out *= 1.0 + drift * np.sin(2 * np.pi * 0.23 * t)
    env = np.minimum(1.0, t / attack) * rel_gate(n, int(dur * SR), rel)
    return out * env / len(detunes)


def i_bass(f, dur, tau=0.55, rel=0.08):
    n = int((dur + rel + 0.05) * SR)
    t = _t(n)
    out = np.sin(2 * np.pi * f * t) + 0.38 * np.sin(2 * np.pi * 2 * f * t) + 0.12 * np.sin(2 * np.pi * 3 * f * t)
    return out * np.exp(-t / tau) * np.minimum(1.0, t / 0.006) * rel_gate(n, int(dur * SR), rel)


def i_sub(f, dur, attack=0.4, rel=0.6):
    n = int((dur + rel) * SR)
    t = _t(n)
    out = np.sin(2 * np.pi * f * t) + 0.2 * np.sin(2 * np.pi * 2 * f * t)
    return out * np.minimum(1.0, t / attack) * rel_gate(n, int(dur * SR), rel)


def i_lead(f, dur, duty=0.3, lp=2600.0, vib=0.006, attack=0.012, rel=0.1):
    n = int((dur + rel + 0.05) * SR)
    t = _t(n)
    vibr = vib * np.minimum(1.0, t / 0.25) * np.sin(2 * np.pi * 5.2 * t)
    ph = np.cumsum(f * (1.0 + vibr)) / SR
    x = np.where((ph % 1.0) < duty, 1.0, -1.0)
    x = fft_filter(x, SR, hi=lp, order=2)
    env = np.minimum(1.0, t / attack) * np.exp(-t / max(dur * 1.5, 0.3)) * rel_gate(n, int(dur * SR), rel)
    return x * env


def i_flute(f, dur, rng, vib=0.008, attack=0.06, rel=0.15, breath=0.05):
    n = int((dur + rel + 0.05) * SR)
    t = _t(n)
    vibr = vib * np.minimum(1.0, t / 0.35) * np.sin(2 * np.pi * 5.0 * t)
    ph = np.cumsum(f * (1.0 + vibr)) / SR
    x = np.sin(2 * np.pi * ph) + 0.25 * np.sin(4 * np.pi * ph) + 0.08 * np.sin(6 * np.pi * ph)
    x += breath * fft_filter(rng.standard_normal(n), SR, lo=1500, hi=5000)
    env = np.minimum(1.0, t / attack) * rel_gate(n, int(dur * SR), rel) * (0.85 + 0.15 * np.sin(2 * np.pi * 4.0 * t))
    return x * env


def i_kick(level=1.0):
    n = int(0.28 * SR)
    t = _t(n)
    f = 46 + 90 * np.exp(-t / 0.035)
    ph = np.cumsum(f) / SR
    out = np.sin(2 * np.pi * ph) * np.exp(-t / 0.11)
    out += 0.12 * np.exp(-t / 0.004) * np.sin(2 * np.pi * 900 * t)
    return out * level


def i_snare(rng, level=1.0):
    n = int(0.22 * SR)
    t = _t(n)
    nz = fft_filter(rng.standard_normal(n), SR, lo=1400, hi=7000) * np.exp(-t / 0.07)
    nz /= np.max(np.abs(nz)) + 1e-9
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.05)
    return (nz * 0.75 + tone * 0.45) * level


def i_hat(rng, open_=False, level=1.0):
    n = int((0.16 if open_ else 0.05) * SR)
    t = _t(n)
    nz = fft_filter(rng.standard_normal(n), SR, lo=6500, hi=13000)
    nz /= np.max(np.abs(nz)) + 1e-9
    return nz * np.exp(-t / (0.07 if open_ else 0.016)) * level


def i_shaker(rng, level=1.0):
    n = int(0.09 * SR)
    t = _t(n)
    nz = fft_filter(rng.standard_normal(n), SR, lo=4500, hi=11000)
    nz /= np.max(np.abs(nz)) + 1e-9
    return nz * np.minimum(1.0, t / 0.012) * np.exp(-t / 0.035) * level


def i_rim(rng, level=1.0):
    n = int(0.05 * SR)
    t = _t(n)
    nz = fft_filter(rng.standard_normal(n), SR, lo=1500, hi=6000) * np.exp(-t / 0.006)
    nz /= np.max(np.abs(nz)) + 1e-9
    return (nz * 0.6 + np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.01) * 0.4) * level


def i_tom(f0=95, f1=42, tau=0.45, level=1.0):
    n = int(0.9 * SR)
    t = _t(n)
    f = f1 + (f0 - f1) * np.exp(-t / 0.08)
    ph = np.cumsum(f) / SR
    return np.sin(2 * np.pi * ph) * np.exp(-t / tau) * level


def wind(n, rng, lo=200.0, hi=1400.0, lfo_cycles=3):
    nz = fft_filter(rng.standard_normal(n), SR, lo=lo, hi=hi, order=2, circular=True)
    nz /= np.max(np.abs(nz)) + 1e-9
    t = np.arange(n) / n
    lfo = 0.55 + 0.45 * np.sin(2 * np.pi * lfo_cycles * t + 1.0)
    return nz * lfo


# --------------------------------------------------------------------------
# Мелодия: блуждание по гамме, сильные доли — на звуках аккорда
# --------------------------------------------------------------------------

RHYTHMS = {
    "flow": [(0, 4), (4, 2), (6, 2), (8, 4), (12, 4)],
    "walk": [(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4)],
    "sync": [(0, 3), (3, 3), (6, 2), (8, 4), (12, 2), (14, 2)],
    "bounce": [(0, 2), (2, 1), (4, 2), (6, 2), (8, 2), (10, 1), (12, 4)],
    "long": [(0, 8), (8, 8)],
    "sparse": [(0, 6), (8, 4)],
    "sigh": [(2, 6), (10, 6)],
    "cadence": [(0, 6), (6, 10)],
}


def melody_phrase(rng, scale, progs, rhythms, start_idx, strong=(0, 4, 8, 12), rest_p=0.0, lo_i=0, hi_i=None):
    """progs — список (root, kind) на такт; rhythms — имена ритмов на такт.
    Возвращает [(bar, step, dur, midi)]. Второй такт каждой пары повторяет
    контур первого (мотив), последний такт — каденция на звук аккорда."""
    hi_i = len(scale) - 1 if hi_i is None else hi_i
    notes = []
    idx = start_idx
    contours = {}
    for bar, ((root, kind), rname) in enumerate(zip(progs, rhythms)):
        pcs = set(chord_pcs(root, kind))
        rhythm = RHYTHMS[rname]
        key = (rname, bar % 2)
        if bar % 2 == 1 and ("m", bar - 1) in contours:
            moves = contours[("m", bar - 1)]
            moves = (moves + [0] * len(rhythm))[:len(rhythm)]
        else:
            moves = [int(rng.choice([-2, -1, -1, 0, 1, 1, 2])) for _ in rhythm]
        contours[("m", bar)] = moves
        for j, (st, du) in enumerate(rhythm):
            if j == 0:
                # старт такта — ближайший звук аккорда к текущей высоте
                cands = [i for i in range(lo_i, hi_i + 1) if scale[i] % 12 in pcs]
                idx = min(cands, key=lambda i: abs(i - idx)) if cands else idx
            else:
                idx = int(np.clip(idx + moves[j], lo_i, hi_i))
                if st in strong and scale[idx] % 12 not in pcs:
                    cands = [i for i in range(max(lo_i, idx - 2), min(hi_i, idx + 2) + 1) if scale[i] % 12 in pcs]
                    if cands:
                        idx = min(cands, key=lambda i: abs(i - idx))
            if rng.random() < rest_p and j not in (0,):
                continue
            notes.append((bar, st, du, scale[idx]))
    return notes, idx


# --------------------------------------------------------------------------
# Сведение
# --------------------------------------------------------------------------

def master(x, target_rms=0.085, ceiling=0.72):
    """Громкость меряем выше 110 Гц: телефонный динамик низов не играет, а
    тяжёлый саб в измерении иначе приглушал бы всё слышимое."""
    x = x - np.mean(x)
    x = fft_filter(x, SR, lo=35.0, hi=9500.0, order=2, circular=True)
    ref = fft_filter(x, SR, lo=110.0, order=2, circular=True)
    x = x / (np.sqrt(np.mean(ref ** 2)) + 1e-9) * target_rms
    return ceiling * np.tanh(x / ceiling)


def sum_buses(m, gains, sends):
    """gains: имя шины -> усиление; sends: имя шины -> (реверб-доля)."""
    dry = np.zeros(m.n)
    for name, arr in m.buses.items():
        dry += arr * gains.get(name, 1.0)
    return dry


# --------------------------------------------------------------------------
# Дорожки
# --------------------------------------------------------------------------

def _pad_track(m, prog, voicings, bus="pad", gain=0.3, attack=0.5, rel=0.9, harm=6, steps_per_chord=16, warmth=0.72,
               bars_per_chord=1):
    for i, (v, (root, kind)) in enumerate(zip(voicings, prog)):
        bar = i * bars_per_chord
        dur = m.g.sec(16 * bars_per_chord) + 0.05
        for note in v:
            m.add(bus, i_pad(float(mtof(note)), dur, attack=attack, rel=rel, harm=harm, warmth=warmth), bar, 0, gain)


def _render_surface():
    m = Mix("mus_surface", **{k: TRACKS["mus_surface"][k] for k in ("bpm", "bars")})
    C, D_, E, F, G, A, B = 0, 2, 4, 5, 7, 9, 11
    A_sec = [(C, "maj"), (G, "maj"), (A, "min"), (F, "maj"), (C, "maj"), (G, "maj"), (F, "maj"), (G, "maj")]
    B_sec = [(A, "min"), (F, "maj"), (C, "maj"), (G, "maj"), (A, "min"), (F, "maj"), (G, "maj"), (C, "maj")]
    A2 = [(C, "maj"), (G, "maj"), (A, "min"), (F, "maj"), (C, "maj"), (G, "maj"), (F, "maj"), (C, "maj")]
    prog = A_sec + B_sec + A2
    rng = m.rng
    voic = lead_voicings(prog, 55, 74)
    _pad_track(m, prog, voic, gain=0.16, attack=0.7, rel=1.0, harm=5)

    # гитарный перебор: восьмые по звукам аккорда
    pats = [[0, 1, 2, 1, 3, 1, 2, 1], [0, 2, 1, 3, 2, 3, 1, 2]]
    for bar, (root, kind) in enumerate(prog):
        pcs = chord_pcs(root, kind)
        base = 55
        tones = []
        for octv in range(0, 3):
            for pc in sorted(pcs, key=lambda p: (p - base) % 12):
                tones.append(base + ((pc - base) % 12) + 12 * octv)
        pat = pats[1] if 8 <= bar < 16 else pats[0]
        for j, idx in enumerate(pat):
            vel = 0.8 + 0.2 * rng.random() if j % 2 == 0 else 0.55 + 0.2 * rng.random()
            m.add("pluck", i_pluck(float(mtof(tones[idx])), 0.3, tau=0.8), bar, j * 2, 0.45 * vel, jitter=0.004)

    # бас
    for bar, (root, kind) in enumerate(prog):
        b = bass_note(root, 38)
        m.add("bass", i_bass(float(mtof(b)), 0.5), bar, 0, 0.7)
        m.add("bass", i_bass(float(mtof(b + 7)), 0.35), bar, 8, 0.5)
        if bar % 2 == 1:
            m.add("bass", i_bass(float(mtof(b + 12)), 0.2), bar, 14, 0.35)

    # мелодия (со 2-й фразы)
    scale = scale_list(C, MAJ, 67, 88)
    idx = 4
    for ph in range(1, 6):
        b0 = ph * 4
        rh = [["flow", "walk", "flow", "cadence"], ["sync", "flow", "walk", "cadence"]][ph % 2]
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], rh, idx, rest_p=0.1)
        for bar, st, du, mid in notes:
            sig = i_marimba(float(mtof(mid)), m.g.sec(du), tau=0.55) if ph % 2 == 1 else \
                i_flute(float(mtof(mid)), m.g.sec(du), rng, breath=0.03)
            m.add("lead", sig, b0 + bar, st, 0.5 if ph % 2 == 1 else 0.35)

    # лёгкий ритм с 4-го такта
    for bar in range(4, 24):
        for s in (0, 8):
            m.add("perc", i_kick(0.5), bar, s, 0.3)
        for s in range(0, 16, 2):
            m.add("perc", i_shaker(rng, 0.7), bar, s + (1 if False else 0), 0.14 if s % 4 else 0.09, jitter=0.002)
        m.add("perc", i_rim(rng, 0.6), bar, 12, 0.12)

    return _finish(m, {"pad": 1.0, "pluck": 1.0, "bass": 0.9, "lead": 1.0, "perc": 0.9},
                   {"pad": 0.35, "pluck": 0.2, "lead": 0.3, "bass": 0.0, "perc": 0.08}, rt60=1.5)


def _finish(m, gains, sends, rt60=1.6, damp=4800.0, echo=None, seed=11):
    """Реверб-посыл по шинам (циркулярный), затем сумма и мастеринг."""
    out = np.zeros(m.n)
    for i, (name, arr) in enumerate(m.buses.items()):
        g = gains.get(name, 1.0)
        dry = arr * g
        s = sends.get(name, 0.0)
        if echo and name in echo:
            dry = echo_circ(dry, SR, echo[name][0], echo[name][1], taps=echo[name][2])
        if s > 0:
            out += dry + reverb_send(dry, SR, rt60=rt60, damp=damp, seed=seed + i) * s
        else:
            out += dry
    return master(out)


def _render_mine_1():
    m = Mix("mus_mine_1", **{k: TRACKS["mus_mine_1"][k] for k in ("bpm", "bars")})
    rng = m.rng
    A, C, D_, E, F, G = 9, 0, 2, 4, 5, 7
    Asec = [(A, "min"), (A, "min"), (F, "maj"), (F, "maj"), (G, "maj"), (G, "maj"), (E, "min"), (E, "min")]
    Bsec = [(A, "min"), (F, "maj"), (G, "maj"), (E, "min"), (A, "min"), (F, "maj"), (G, "maj"), (G, "maj")]
    A2 = [(A, "min"), (A, "min"), (F, "maj"), (F, "maj"), (G, "maj"), (G, "maj"), (E, "min"), (A, "min")]
    prog = Asec + Bsec + A2
    voic = lead_voicings(prog, 52, 70)
    _pad_track(m, prog, voic, gain=0.2, attack=1.0, rel=1.2, harm=5, warmth=0.62)
    # дрон
    m.add("drone", i_sub(float(mtof(45)), m.g.sec(16 * 24) - 1.0, attack=0.3, rel=1.0), 0, 0, 0.5)
    m.add("drone", i_sub(float(mtof(52)), m.g.sec(16 * 24) - 1.0, attack=0.3, rel=1.0), 0, 0, 0.18)

    # пульс баса и «сердцебиение»
    for bar, (root, kind) in enumerate(prog):
        b = bass_note(root, 33)
        m.add("bass", i_bass(float(mtof(b + 12)), 0.9, tau=0.9), bar, 0, 0.55)
        if bar % 2 == 1:
            m.add("bass", i_bass(float(mtof(b + 19)), 0.4, tau=0.5), bar, 10, 0.3)
        m.add("perc", i_kick(0.45), bar, 0, 0.28)
        m.add("perc", i_kick(0.35), bar, 3, 0.16)

    # разреженные плитки марими́бы по пентатонике ля-минор
    pent = scale_list(9, [0, 3, 5, 7, 10], 57, 84)
    for bar in range(24):
        pcs = set(chord_pcs(*prog[bar]))
        for st in range(0, 16):
            p = 0.22 if st % 4 == 0 else 0.1
            if bar < 2:
                p *= 0.3
            if rng.random() < p:
                cand = [x for x in pent if x % 12 in pcs] if st % 4 == 0 else pent
                note = int(rng.choice(cand))
                m.add("mar", i_marimba(float(mtof(note)), 0.2, tau=0.6), bar, st, 0.34 * (0.6 + 0.4 * rng.random()))

    # мотив — колокол, по фразам
    scale = scale_list(A, MIN, 69, 88)
    idx = 3
    for ph in (2, 3, 4, 5):
        b0 = ph * 4
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], ["sparse", "sigh", "sparse", "long"], idx, rest_p=0.0)
        for bar, st, du, mid in notes:
            m.add("bell", i_glass(float(mtof(mid)), m.g.sec(du), tau=1.2), b0 + bar, st, 0.3)

    m.add("wind", wind(m.n, rng, 180, 1100, lfo_cycles=3), 0, 0, 0.1)
    return _finish(m, {"pad": 1.0, "drone": 1.0, "bass": 0.9, "perc": 0.8, "mar": 1.0, "bell": 1.0, "wind": 1.0},
                   {"pad": 0.35, "mar": 0.45, "bell": 0.6, "drone": 0.1, "bass": 0.0, "perc": 0.1, "wind": 0.3},
                   rt60=2.0, echo={"mar": (m.g.sec(6) , 0.42, 3), "bell": (m.g.sec(8), 0.35, 3)})


def _render_mine_2():
    m = Mix("mus_mine_2", **{k: TRACKS["mus_mine_2"][k] for k in ("bpm", "bars")})
    rng = m.rng
    D_, Bb, F, C, G = 2, 10, 5, 0, 7
    prog = [(D_, "min"), (Bb, "maj"), (F, "maj"), (C, "maj")] * 2 + \
           [(G, "min"), (D_, "min"), (Bb, "maj"), (F, "maj"), (G, "min"), (D_, "min"), (C, "maj"), (C, "maj")] + \
           [(D_, "min"), (Bb, "maj"), (F, "maj"), (C, "maj")]
    voic = lead_voicings(prog, 50, 69)
    _pad_track(m, prog, voic, gain=0.22, attack=1.2, rel=1.4, harm=6, warmth=0.66)
    for bar, (root, kind) in enumerate(prog):
        b = bass_note(root, 31)
        m.add("sub", i_sub(float(mtof(b + 12)), m.g.sec(14), attack=0.25, rel=0.8), bar, 0, 0.5)
        if bar % 2 == 0:
            m.add("perc", i_tom(80, 40, 0.5, 0.5), bar, 0, 0.4)
            m.add("perc", i_tom(70, 38, 0.4, 0.35), bar, 6, 0.25)

    # стеклянные арпеджио (разреженные восьмые)
    for bar, (root, kind) in enumerate(prog):
        pcs = chord_pcs(root, kind)
        tones = [60 + ((pc - 60) % 12) + 12 * o for o in range(0, 2) for pc in sorted(pcs, key=lambda p: (p - 60) % 12)]
        pat = [0, 2, 1, 4, 2, 5, 3, 1]
        for j, ti in enumerate(pat):
            if (bar + j) % 3 == 1 or rng.random() < 0.15:
                continue
            m.add("arp", i_glass(float(mtof(tones[ti % len(tones)])), 0.3, tau=0.9), bar, j * 2,
                  0.28 * (0.6 + 0.4 * rng.random()), jitter=0.004)

    # флейта: фразы с 3-го такта через раз
    scale = scale_list(D_, MIN, 62, 84)
    idx = 4
    for ph in range(0, 5):
        b0 = ph * 4
        if ph == 0:
            continue
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], ["long", "sparse", "sigh", "cadence"], idx)
        for bar, st, du, mid in notes:
            m.add("lead", i_flute(float(mtof(mid)), m.g.sec(du) * 0.95, rng, vib=0.01, attack=0.12, breath=0.04),
                  b0 + bar, st, 0.34)
    m.add("wind", wind(m.n, rng, 150, 900, lfo_cycles=2), 0, 0, 0.08)
    return _finish(m, {"pad": 1.0, "sub": 1.0, "perc": 0.9, "arp": 1.0, "lead": 1.0, "wind": 1.0},
                   {"pad": 0.4, "arp": 0.6, "lead": 0.5, "perc": 0.15, "sub": 0.05, "wind": 0.3},
                   rt60=2.4, echo={"arp": (m.g.sec(3), 0.4, 3)})


def _render_deep():
    m = Mix("mus_deep", **{k: TRACKS["mus_deep"][k] for k in ("bpm", "bars")})
    rng = m.rng
    Fs, D_, B, Cs, A, E = 6, 2, 11, 1, 9, 4
    prog = [(Fs, "min9"), (D_, "maj7"), (B, "min7"), (Cs, "min7")] * 2
    voic = lead_voicings(prog, 46, 69)
    # каждый аккорд — два такта
    _pad_track(m, prog, voic, gain=0.26, attack=2.4, rel=2.6, harm=5, warmth=0.55, bars_per_chord=2)
    total = m.g.sec(16 * 16)
    m.add("drone", i_sub(float(mtof(42)), total - 1.5, attack=0.4, rel=1.5), 0, 0, 0.42)
    m.add("drone", i_sub(float(mtof(49)), total - 1.5, attack=0.4, rel=1.5), 0, 0, 0.22)
    m.add("drone", i_sub(float(mtof(30)), total - 1.5, attack=0.4, rel=1.5), 0, 0, 0.25)
    # далёкие стеклянные колокола, F#-минорная пентатоника
    pent = scale_list(Fs, [0, 3, 5, 7, 10], 66, 90)
    t_steps = 0
    while t_steps < 16 * 16 - 8:
        st = t_steps
        bar, step = divmod(st, 16)
        note = int(rng.choice(pent))
        m.add("bell", i_glass(float(mtof(note)), 1.0, tau=2.2), bar, step, 0.34 * (0.5 + 0.5 * rng.random()))
        t_steps += int(rng.choice([6, 8, 10, 14, 20]))
    # низкий «бум» раз в 4 такта
    for bar in range(0, 16, 4):
        m.add("perc", i_tom(70, 34, 0.9, 0.6), bar, 0, 0.5)
    # «кит» — медленный глиссандо раз в 8 тактов
    for bar, f0, f1 in [(3, 520.0, 380.0), (11, 440.0, 620.0)]:
        n = int(5.0 * SR)
        t = np.arange(n) / SR
        f = f0 + (f1 - f0) * (t / 5.0)
        ph = np.cumsum(f * (1.0 + 0.012 * np.sin(2 * np.pi * 0.7 * t))) / SR
        env = np.sin(np.pi * t / 5.0) ** 2
        m.add("whale", np.sin(2 * np.pi * ph) * env, bar, 8, 0.12)
    m.add("wind", wind(m.n, rng, 120, 900, lfo_cycles=2), 0, 0, 0.16)
    m.add("wind", wind(m.n, rng, 2000, 6000, lfo_cycles=5), 0, 0, 0.025)
    return _finish(m, {"pad": 1.0, "drone": 1.0, "bell": 1.0, "perc": 1.0, "whale": 1.0, "wind": 1.0},
                   {"pad": 0.5, "bell": 0.9, "perc": 0.25, "whale": 0.9, "drone": 0.1, "wind": 0.1},
                   rt60=3.4, damp=3800.0)


def _render_boss():
    m = Mix("mus_boss", **{k: TRACKS["mus_boss"][k] for k in ("bpm", "bars")})
    rng = m.rng
    E, C, G, D_, A, B = 4, 0, 7, 2, 9, 11
    P1 = [(E, "min"), (C, "maj"), (G, "maj"), (D_, "maj")]
    P2 = [(A, "min"), (E, "min"), (C, "maj"), (D_, "maj")]
    P3 = [(A, "min"), (E, "min"), (B, "min"), (B, "min")]
    P4 = [(C, "maj"), (D_, "maj"), (E, "min"), (E, "min")]
    prog = P1 + P1 + P2 + P3 + P1 + P1 + P4
    nb = len(prog)
    assert nb == 28
    voic = lead_voicings([(r, "pw") for r, _ in prog], 52, 72)
    _pad_track(m, [(r, "pw") for r, _ in prog], voic, gain=0.2, attack=0.15, rel=0.3, harm=6, warmth=0.6)
    # бочка, малый, хэт
    for bar in range(nb):
        for s in (0, 4, 8, 12):
            m.add("perc", i_kick(0.9), bar, s, 0.5 if s % 8 == 0 else 0.4)
        for s in (4, 12):
            m.add("perc", i_snare(rng, 0.8), bar, s, 0.32)
        for s in range(16):
            m.add("perc", i_hat(rng, open_=(s == 14), level=0.8), bar, s, 0.10 if s % 4 else 0.14, jitter=0.0015)
        if bar % 4 == 3:
            for s in (12, 13, 14, 15):
                m.add("perc", i_snare(rng, 0.7), bar, s, 0.2 + 0.03 * (s - 12))
    # пульсирующий бас
    for bar, (root, kind) in enumerate(prog):
        b = bass_note(root, 40)
        for s in range(0, 16, 2):
            note = b + (12 if s in (6, 14) else 0)
            m.add("bass", i_bass(float(mtof(note)), 0.12, tau=0.18), bar, s, 0.6 if s % 4 == 0 else 0.45)
    # 16-е арпеджио
    for bar, (root, kind) in enumerate(prog):
        pcs = chord_pcs(root, kind)
        tones = [64 + ((pc - 64) % 12) + 12 * o for o in range(0, 2) for pc in sorted(pcs, key=lambda p: (p - 64) % 12)]
        pat = [0, 1, 2, 1, 3, 2, 4, 2, 0, 1, 2, 1, 3, 4, 5, 4]
        if bar < 4:
            continue
        for j, ti in enumerate(pat):
            m.add("arp", i_lead(float(mtof(tones[ti % len(tones)])), 0.11, duty=0.25, lp=2200, vib=0.0, attack=0.004, rel=0.04),
                  bar, j, 0.2 if j % 4 == 0 else 0.14, jitter=0.0008)
    # мелодия
    scale = scale_list(E, MIN, 64, 86)
    idx = 4
    for ph in range(2, 7):
        b0 = ph * 4
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], ["sync", "flow", "sync", "cadence"], idx)
        for bar, st, du, mid in notes:
            m.add("lead", i_lead(float(mtof(mid)), m.g.sec(du) * 0.9, duty=0.5, lp=2400, vib=0.007, attack=0.01), b0 + bar, st, 0.3)
    return _finish(m, {"pad": 1.0, "perc": 1.0, "bass": 1.0, "arp": 1.0, "lead": 1.0},
                   {"pad": 0.2, "perc": 0.12, "lead": 0.25, "arp": 0.2, "bass": 0.0}, rt60=1.0, damp=4200.0)


def _render_story():
    m = Mix("mus_story", **{k: TRACKS["mus_story"][k] for k in ("bpm", "bars")})
    rng = m.rng
    A, F, C, G, D_, E = 9, 5, 0, 7, 2, 4
    prog = [(A, "min"), (F, "maj"), (C, "maj"), (G, "maj")] * 2 + \
           [(D_, "min"), (A, "min"), (F, "maj"), (C, "maj"), (D_, "min"), (A, "min"), (G, "maj"), (E, "min")] + \
           [(F, "maj"), (C, "maj"), (G, "maj"), (A, "min")]
    voic = lead_voicings(prog, 52, 71)
    _pad_track(m, prog, voic, gain=0.2, attack=1.0, rel=1.2, harm=6, warmth=0.62)
    # арпеджио электропиано
    for bar, (root, kind) in enumerate(prog):
        pcs = chord_pcs(root, kind)
        tones = [57 + ((pc - 57) % 12) + 12 * o for o in range(0, 3) for pc in sorted(pcs, key=lambda p: (p - 57) % 12)]
        pat = [0, 2, 1, 3, 2, 4, 3, 1] if bar % 2 == 0 else [0, 1, 3, 2, 4, 2, 3, 1]
        for j, ti in enumerate(pat):
            vel = 1.0 if j % 4 == 0 else 0.62
            m.add("ep", i_epiano(float(mtof(tones[ti % len(tones)])), 0.45), bar, j * 2, 0.34 * vel, jitter=0.005)
        b = bass_note(root, 36)
        m.add("bass", i_sub(float(mtof(b)), m.g.sec(15), attack=0.1, rel=0.5), bar, 0, 0.5)
    scale = scale_list(A, MIN, 67, 86)
    idx = 4
    for ph in range(1, 5):
        b0 = ph * 4
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], ["long", "sigh", "sparse", "cadence"], idx)
        for bar, st, du, mid in notes:
            m.add("lead", i_flute(float(mtof(mid)), m.g.sec(du) * 0.97, rng, vib=0.009, attack=0.09, breath=0.035),
                  b0 + bar, st, 0.36)
    return _finish(m, {"pad": 1.0, "ep": 1.0, "bass": 1.0, "lead": 1.0},
                   {"pad": 0.5, "ep": 0.5, "lead": 0.6, "bass": 0.05}, rt60=2.6, damp=4200.0)


def _render_shop():
    m = Mix("mus_shop", **{k: TRACKS["mus_shop"][k] for k in ("bpm", "bars")})
    rng = m.rng
    G, E, C, D_, B = 7, 4, 0, 2, 11
    Asec = [(G, "maj"), (E, "min"), (C, "maj"), (D_, "maj")] * 2
    Bsec = [(C, "maj"), (D_, "maj"), (B, "min"), (E, "min"), (C, "maj"), (D_, "maj"), (G, "maj"), (G, "maj")]
    prog = Asec + Bsec + Asec
    voic = lead_voicings(prog, 55, 74)
    _pad_track(m, prog, voic, gain=0.1, attack=0.3, rel=0.5, harm=5, warmth=0.6)
    # шагающий бас
    for bar, (root, kind) in enumerate(prog):
        b = bass_note(root, 38)
        third = 3 if kind == "min" else 4
        walk = [b, b + third, b + 7, b + third]
        for q, note in enumerate(walk):
            m.add("bass", i_bass(float(mtof(note)), 0.2, tau=0.3), bar, q * 4, 0.6 if q == 0 else 0.45)
    # аккорды-«скэнк» марими́бой на слабые доли
    for bar, v in enumerate(voic):
        for s in (6, 14):
            for note in v:
                m.add("chord", i_marimba(float(mtof(note)), 0.12, tau=0.3), bar, s, 0.1)
    # ритм
    for bar in range(24):
        for s in (0, 8):
            m.add("perc", i_kick(0.6), bar, s, 0.35)
        for s in (4, 12):
            m.add("perc", i_rim(rng, 0.8), bar, s, 0.2)
        for s in range(0, 16, 2):
            m.add("perc", i_shaker(rng, 0.8), bar, s + 1 if False else s, 0.1 if s % 4 else 0.13, jitter=0.002)
    # мелодия — мягкий квадрат, подпрыгивающий ритм
    scale = scale_list(G, MAJ, 67, 88)
    idx = 4
    for ph in range(0, 6):
        b0 = ph * 4
        rh = [["bounce", "walk", "bounce", "cadence"], ["sync", "bounce", "walk", "cadence"]][ph % 2]
        notes, idx = melody_phrase(rng, scale, prog[b0:b0 + 4], rh, idx, rest_p=0.06)
        for bar, st, du, mid in notes:
            m.add("lead", i_lead(float(mtof(mid)), m.g.sec(du) * 0.85, duty=0.25, lp=2800, vib=0.004, attack=0.008),
                  b0 + bar, st, 0.22 if ph % 2 == 0 else 0.2)
    # искры колокольчиков на последней фразе секций
    for bar in (7, 15, 23):
        for j, mid in enumerate([86, 83, 79, 83, 86, 91]):
            m.add("bell", i_glass(float(mtof(mid)), 0.2, tau=0.6), bar, 8 + j, 0.12)
    return _finish(m, {"pad": 1.0, "bass": 1.0, "chord": 1.0, "perc": 1.0, "lead": 1.0, "bell": 1.0},
                   {"pad": 0.3, "lead": 0.25, "chord": 0.2, "bell": 0.4, "bass": 0.0, "perc": 0.05}, rt60=1.0, damp=5000.0)


_RENDER = {
    "mus_surface": _render_surface,
    "mus_mine_1": _render_mine_1,
    "mus_mine_2": _render_mine_2,
    "mus_deep": _render_deep,
    "mus_boss": _render_boss,
    "mus_story": _render_story,
    "mus_shop": _render_shop,
}


def render(name):
    return _RENDER[name]()
