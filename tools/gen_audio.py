#!/usr/bin/env python3
"""Генератор всего звука игры: эффекты (audio/sfx/*.wav), музыку
(audio/music/*.ogg) и каталог audio/catalog.json, который читает SfxService.

    python3 tools/gen_audio.py                # всё
    python3 tools/gen_audio.py --sfx          # только эффекты
    python3 tools/gen_audio.py --music        # только музыку
    python3 tools/gen_audio.py --only coin,dig_dirt,mus_boss
    python3 tools/gen_audio.py --check        # проверить уже собранное (швы, размер)

Звук — синтез на numpy (шум + огибающие, FM, пилы/квадраты, чиптюн): никаких
сэмплов со стороны. Детерминирован (сид от имени звука): повторный запуск даёт
те же файлы. Это заглушки уровня «программист собрал аккуратно»; если владелец
получит настоящую озвучку, она кладётся в те же пути с тем же именем.

Эффекты — моно 22,05 кГц, 16 бит WAV. Музыка — моно 32 кГц, Vorbis (ffmpeg).
Швы петель музыки проверяются здесь же: каждая дорожка собирается как
циркулярный буфер (хвосты нот и реверберация заворачиваются), так что стык
периодичен по построению; после кодирования файл декодируется обратно и
сравнивается скачок на стыке.
"""
import argparse
import json
import os
import subprocess
import sys
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "audio")

import audio_dsp as D  # noqa: E402
import audio_sfx  # noqa: E402

BUDGET_MB = 12.0


def write_wav(path, x, sr=D.SR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(D.to_int16(x).tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        raw = w.readframes(w.getnframes())
        return np.frombuffer(raw, dtype=np.int16).astype(float) / 32768.0, w.getframerate()


def write_ogg(path, x, sr, quality=3):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    pcm = D.to_int16(x).tobytes()
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(sr), "-ac", "1",
           "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", str(quality), path]
    subprocess.run(cmd, input=pcm, check=True)


def decode_ogg(path, sr):
    cmd = ["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ar", str(sr), "-ac", "1", "pipe:1"]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(float) / 32768.0


def seam_report(x):
    """Скачок на стыке петли относительно обычного шага между отсчётами.
    Возвращает (скачок, 99-й процентиль |Δ|, отношение)."""
    d = np.abs(np.diff(x))
    jump = abs(float(x[0] - x[-1]))
    ref = float(np.percentile(d, 99.5)) + 1e-9
    return jump, ref, jump / ref


# --------------------------------------------------------------------------

def build_sfx(only):
    catalog = {}
    total = 0
    for name, spec in audio_sfx.REG.items():
        if only and name not in only:
            continue
        files = []
        for v in range(spec["variants"]):
            rng = D.rng_for("%s#%d" % (name, v))
            x = spec["fn"](rng, v)
            if spec["loop"]:
                x = x / (np.max(np.abs(x)) + 1e-9) * spec["peak"]
                x = x - np.mean(x)
            else:
                x = D.finish(x, spec["peak"])
            fname = "%s.wav" % name if spec["variants"] == 1 else "%s_%d.wav" % (name, v + 1)
            path = os.path.join(OUT, "sfx", fname)
            write_wav(path, x)
            total += os.path.getsize(path)
            files.append("sfx/" + fname)
        entry = {"files": files, "db": spec["db"], "pv": spec["pv"], "prio": spec["prio"],
                 "voices": spec["voices"], "cd": spec["cd"]}
        if spec["duck"]:
            entry["duck"] = spec["duck"]
        if spec["loop"]:
            entry["loop"] = True
        catalog[name] = entry
    return catalog, total


def build_music(only):
    import audio_music
    catalog = {}
    total = 0
    problems = []
    for name, spec in audio_music.TRACKS.items():
        if only and name not in only:
            continue
        x = audio_music.render(name)
        jump, ref, ratio = seam_report(x)
        path = os.path.join(OUT, "music", name + ".ogg")
        write_ogg(path, x, D.MSR, spec.get("quality", 3))
        dec = decode_ogg(path, D.MSR)
        # Кодек добавляет крошечные искажения у краёв; сравниваем скачок на стыке
        # после декодирования с тем же эталоном.
        n = min(len(dec), len(x))
        j2, r2, ratio2 = seam_report(dec[:n]) if n > 1000 else (0, 0, 0)
        dur = len(x) / D.MSR
        size = os.path.getsize(path)
        total += size
        peak = float(np.max(np.abs(x)))
        rms = float(np.sqrt(np.mean(x ** 2)))
        print("  %-12s %5.1f с  %4d КБ  пик %.2f  rms %.3f  шов: исх %.2f ед., после кодека %.2f ед., длина dec/исх %d/%d"
              % (name, dur, size // 1024, peak, rms, ratio, ratio2, len(dec), len(x)))
        if ratio > 3.0 or ratio2 > 3.0:
            problems.append("%s: шов петли заметен (%.1f / %.1f)" % (name, ratio, ratio2))
        if abs(len(dec) - len(x)) > 64:
            problems.append("%s: длина после кодека %d, ожидалось %d" % (name, len(dec), len(x)))
        catalog[name] = {"file": "music/%s.ogg" % name, "db": spec.get("db", -3.0), "bpm": spec.get("bpm", 0)}
    for alias, target in audio_music.ALIASES.items():
        if only and alias not in only and target not in only:
            continue
        catalog[alias] = {"alias": target}
    return catalog, total, problems


def dir_size(path):
    s = 0
    for r, _, fs in os.walk(path):
        for f in fs:
            if f.endswith((".wav", ".ogg", ".json")):
                s += os.path.getsize(os.path.join(r, f))
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sfx", action="store_true")
    ap.add_argument("--music", action="store_true")
    ap.add_argument("--only", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    only = set(s for s in a.only.split(",") if s)
    want_sfx = a.sfx or (not a.music and not only) or any(not n.startswith("mus_") for n in only)
    want_music = a.music or (not a.sfx and not only) or any(n.startswith("mus_") for n in only)

    cat_path = os.path.join(OUT, "catalog.json")
    old = {}
    if os.path.exists(cat_path):
        with open(cat_path, encoding="utf-8") as f:
            old = json.load(f)
    catalog = {"version": 1, "sfx": old.get("sfx", {}), "music": old.get("music", {})}

    problems = []
    if a.check:
        import audio_music
        for name in audio_music.TRACKS:
            p = os.path.join(OUT, "music", name + ".ogg")
            if not os.path.exists(p):
                problems.append("нет " + p)
                continue
            dec = decode_ogg(p, D.MSR)
            j, r, ratio = seam_report(dec)
            print("%-12s %.1f с, шов %.2f ед." % (name, len(dec) / D.MSR, ratio))
            if ratio > 3.0:
                problems.append("%s: шов" % name)
    else:
        if want_sfx:
            cs, tot = build_sfx(only)
            catalog["sfx"].update(cs)
            print("эффекты: %d id, %.0f КБ" % (len(cs), tot / 1024))
        if want_music:
            cm, tot, pr = build_music(only)
            catalog["music"].update(cm)
            problems += pr
            print("музыка: %d id, %.0f КБ" % (len(cm), tot / 1024))
        os.makedirs(OUT, exist_ok=True)
        with open(cat_path, "w", encoding="utf-8") as f:
            json.dump(catalog, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write("\n")

    size_mb = dir_size(OUT) / 1048576.0
    print("итого audio/: %.2f МБ (бюджет %.0f МБ)" % (size_mb, BUDGET_MB))
    if size_mb > BUDGET_MB:
        problems.append("звук тяжелее бюджета")
    for p in problems:
        print("ПРОБЛЕМА:", p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
