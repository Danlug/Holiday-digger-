"""Примитивы синтеза для tools/gen_audio.py: осцилляторы, огибающие, фильтры
через FFT, реверберация. Только numpy; всё векторизовано.

Фильтры нулевой фазы (по модулю АЧХ Баттерворта) — для коротких шумовых
всплесков это нормально, а для музыки даёт нужное: фильтр на полной длине
петли без нулевого дополнения — циркулярный, то есть стык петли не страдает.
"""
import numpy as np

SR = 22050     # звуки интерфейса и эффектов
MSR = 32000    # музыка


def mtof(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=float) - 69.0) / 12.0)


def rng_for(name):
    import zlib
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


# --------------------------------------------------------------------------
# Осцилляторы и огибающие
# --------------------------------------------------------------------------

def tvec(dur, sr=SR):
    return np.arange(int(round(dur * sr))) / sr


def phase(freq, n, sr=SR):
    """Накопленная фаза в циклах; freq — число или массив длины n."""
    f = np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=float)
    return np.cumsum(f) / sr


def osc(kind, freq, n, sr=SR, duty=0.5):
    p = phase(freq, n, sr)
    if kind == "sin":
        return np.sin(2 * np.pi * p)
    q = p % 1.0
    if kind == "saw":
        return 2 * q - 1
    if kind == "sqr":
        return np.where(q < duty, 1.0, -1.0)
    if kind == "tri":
        return 2 * np.abs(2 * q - 1) - 1
    raise ValueError(kind)


def sweep(f0, f1, n, curve=1.0):
    """Частота от f0 к f1 за n отсчётов; curve>1 — быстрее в начале."""
    u = np.linspace(0.0, 1.0, n)
    u = 1.0 - (1.0 - u) ** curve
    return f0 * (f1 / f0) ** u


def env_exp(n, sr, decay, attack=0.002):
    t = np.arange(n) / sr
    e = np.exp(-t / decay)
    if attack > 0:
        e = e * np.minimum(1.0, t / attack)
    return e


def env_adsr(n, sr, a, d, s, r):
    t = np.arange(n) / sr
    dur = n / sr
    e = np.ones(n)
    e = np.where(t < a, t / max(a, 1e-6), e)
    e = np.where((t >= a) & (t < a + d), 1.0 - (1.0 - s) * (t - a) / max(d, 1e-6), e)
    e = np.where(t >= a + d, s, e)
    rel = np.clip((dur - t) / max(r, 1e-6), 0.0, 1.0)
    return e * rel


def env_ar(n, sr, a, r_power=2.0):
    """Нарастание за a секунд и плавный спад к концу буфера."""
    t = np.arange(n) / sr
    up = np.minimum(1.0, t / max(a, 1e-6))
    down = (1.0 - np.arange(n) / max(n - 1, 1)) ** r_power
    return up * down


# --------------------------------------------------------------------------
# Фильтры (FFT)
# --------------------------------------------------------------------------

def fft_filter(x, sr, lo=None, hi=None, order=2, circular=False):
    """Полосовой/ФНЧ/ФВЧ по модулю Баттерворта. circular=True — без нулевого
    дополнения (для зацикленной музыки и петель)."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    N = n if circular else 1 << int(np.ceil(np.log2(max(2 * n, 16))))
    X = np.fft.rfft(x, N)
    f = np.fft.rfftfreq(N, 1.0 / sr)
    g = np.ones_like(f)
    if hi is not None:
        g = g / np.sqrt(1.0 + (f / hi) ** (2 * order))
    if lo is not None:
        ff = np.maximum(f, 1e-6)
        g = g / np.sqrt(1.0 + (lo / ff) ** (2 * order))
    y = np.fft.irfft(X * g, N)
    return y[:n]


def noise(n, rng):
    return rng.standard_normal(n)


def bnoise(n, rng, sr=SR, lo=None, hi=None, order=2):
    return fft_filter(rng.standard_normal(n), sr, lo, hi, order)


def crush(x, bits=6):
    q = 2.0 ** (bits - 1)
    return np.round(x * q) / q


def hold(x, k):
    """Прореживание с удержанием (чиптюн-«грязь»)."""
    k = max(1, int(k))
    return np.repeat(x[::k], k)[: len(x)]


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive) if drive > 0 else x


# --------------------------------------------------------------------------
# Склейка
# --------------------------------------------------------------------------

def silence(dur, sr=SR):
    return np.zeros(int(round(dur * sr)))


def place(buf, sig, start):
    """Добавляет sig в buf с позиции start (без заворота; обрезается)."""
    start = int(start)
    if start >= len(buf):
        return buf
    end = min(len(buf), start + len(sig))
    if end > start:
        buf[start:end] += sig[: end - start]
    return buf


def place_wrap(buf, sig, start):
    """То же, но хвост заворачивается в начало: нота в конце петли звучит
    поверх начала — так петля музыки не имеет шва."""
    n = len(buf)
    start = int(start) % n
    m = len(sig)
    if m >= n:
        # очень длинный звук: сворачиваем целыми кругами
        for k in range(0, m, n):
            part = sig[k:k + n]
            idx = (start + k + np.arange(len(part))) % n
            np.add.at(buf, idx, part)
        return buf
    end = start + m
    if end <= n:
        buf[start:end] += sig
    else:
        cut = n - start
        buf[start:] += sig[:cut]
        buf[:end - n] += sig[cut:]
    return buf


def reverb_circ(x, sr, rt60=1.6, wet=0.25, predelay=0.012, damp=4500.0, seed=7):
    """Реверберация циркулярной сверткой с шумовым откликом: хвост
    заворачивается через границу петли, шва не остаётся."""
    n = len(x)
    rng = np.random.default_rng(seed)
    L = min(n - 1, int(rt60 * 1.15 * sr))
    t = np.arange(L) / sr
    ir = rng.standard_normal(L) * np.exp(-6.9 * t / rt60)
    ir = fft_filter(ir, sr, lo=120.0, hi=damp, order=1)
    pd = int(predelay * sr)
    full = np.zeros(n)
    full[pd:pd + L] = ir[: max(0, min(L, n - pd))]
    full /= np.sqrt(np.sum(full ** 2)) + 1e-9
    y = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(full), n)
    return x * (1.0 - wet * 0.35) + y * wet * 1.6


def reverb_send(x, sr, rt60=1.6, predelay=0.012, damp=4500.0, seed=7):
    """Только «мокрый» сигнал реверберации (циркулярный, без сухого): им
    пользуется сведение музыки, подмешивая по своему уровню."""
    n = len(x)
    rng = np.random.default_rng(seed)
    L = min(n - 1, int(rt60 * 1.15 * sr))
    t = np.arange(L) / sr
    ir = rng.standard_normal(L) * np.exp(-6.9 * t / rt60)
    ir = fft_filter(ir, sr, lo=120.0, hi=damp, order=1)
    pd = int(predelay * sr)
    full = np.zeros(n)
    full[pd:pd + L] = ir[: max(0, min(L, n - pd))]
    full /= np.sqrt(np.sum(full ** 2)) + 1e-9
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(full), n)


def reverb_tail(x, sr, rt60=0.5, wet=0.2, damp=5000.0, seed=3):
    """Реверберация для разовых звуков: хвост удлиняет сигнал."""
    pad = int(rt60 * 1.1 * sr)
    xp = np.concatenate([x, np.zeros(pad)])
    n = len(xp)
    rng = np.random.default_rng(seed)
    t = np.arange(pad) / sr
    ir = rng.standard_normal(pad) * np.exp(-6.9 * t / rt60)
    ir = fft_filter(ir, sr, lo=200.0, hi=damp, order=1)
    ir[0] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    N = 1 << int(np.ceil(np.log2(2 * n)))
    y = np.fft.irfft(np.fft.rfft(xp, N) * np.fft.rfft(ir, N), N)[:n]
    return xp + y * wet * 1.6


def echo_circ(x, sr, delay_s, feedback=0.4, taps=4, lowpass=3500.0):
    """Эхо с обратной связью, циркулярное (для петель)."""
    n = len(x)
    out = x.copy()
    d = int(delay_s * sr)
    cur = x
    for _ in range(taps):
        cur = np.roll(cur, d) * feedback
        if lowpass:
            cur = fft_filter(cur, sr, hi=lowpass, order=1, circular=True)
        out = out + cur
    return out


# --------------------------------------------------------------------------
# Выход
# --------------------------------------------------------------------------

def finish(x, peak=0.8, fade_in=0.0008, fade_out=0.008, sr=SR):
    x = np.asarray(x, dtype=float)
    x = x - np.mean(x)
    fi = max(1, int(fade_in * sr))
    fo = max(1, int(fade_out * sr))
    x[:fi] *= np.linspace(0.0, 1.0, fi)
    x[-fo:] *= np.linspace(1.0, 0.0, fo)
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def to_int16(x):
    return np.clip(np.round(np.asarray(x) * 32767.0), -32768, 32767).astype(np.int16)
