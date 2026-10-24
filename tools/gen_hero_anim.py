#!/usr/bin/env python3
"""gen_hero_anim.py — недостающие позы героя из его же авторских кадров.

Авторские листы (art/character/idle.png и др.) НЕ правятся: этот скрипт берёт
кадр стойки idle.png[0] и «собирает» из него позы бумажной куклой — голова,
корпус, две руки и две ноги вырезаются по маскам и переставляются
(поворот вокруг сустава, перенос, сжатие голени). Ничего не рисуется заново,
кроме век и рта на лице: цвета, обводка и штриховка — те же пиксели, что у
художника.

  python3 tools/gen_hero_anim.py        # перегенерировать три листа
  python3 tools/gen_hero_anim.py --preview <каталог>   # + крупные превью ×4

Листы (кадр 144×144, голова на той же оси x ≈ 71, что у idle/walk — ГДД §15.1):

  jump.png    9 кадров: 0 присел, 1 толчок, 2 подъём, 3 вершина, 4 падение,
              5 быстрое падение, 6 выпрямление после приседа, 7 вершина (второй
              такт зависания), 8 подъём пониже
  hurt.png    2 кадра: 0 «ой» (отшатнулся, зажмурился), 1 «в отключке»
  idle_x.png  5 кадров: 0 моргнул, 1-2 оглядывается, 3-4 постукивает ногой

Порядок кадров зашит в scripts/player/character_view.gd (JUMP_FRAMES,
HURT_FRAMES, IDLE_X) и в tests/test_hero_anim.gd — менять вместе.
"""

import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Куклу собирает из АВТОРСКОЙ нарезки и кладёт результат туда же: в
# art/character/ кадры попадают только через tools/gen_hero_art.py, который
# перерисовывает их чётким пиксель-артом (ветка «hero-art»). После этого
# скрипта: python3 tools/gen_hero_art.py jump hurt idle_x
CHAR = os.path.join(ROOT, "art", "_source", "hero_cut")
FW = FH = 144

# --- геометрия стойки idle.png[0] (координаты кадра 144×144) ---------------
NECK_Y = 53                      # ниже — плечи, выше — голова
HEAD_PIVOT = (70.0, 53.0)        # основание шеи
SHOULDER_L = (55.0, 64.0)        # плечо слева на экране
SHOULDER_R = (85.0, 64.0)
HIP_Y = 92                       # линия бёдер
KNEE_END_Y = 126                 # конец штанины, выше — шнурки/ботинок
SOLE_Y = 137                     # подошва
LEG_SPLIT_X = 70.5               # между ногами
HIP_PIVOT_L = (63.0, 92.0)
HIP_PIVOT_R = (78.0, 92.0)
ARM_L_X = 59                     # рука слева: x <= 59, справа: x >= 83
ARM_R_X = 83
ARM_Y0, ARM_Y1 = 58, 102         # рукав и кисть по вертикали
ARM_SKIN_Y = 70                  # ниже — голая рука, выше — рукав (остаётся на корпусе)
SKIN = (240, 196, 160)
LASH = (62, 40, 32)


def load_frame(sheet, index):
    im = Image.open(os.path.join(CHAR, sheet + ".png")).convert("RGBA")
    return np.asarray(im.crop((index * FW, 0, (index + 1) * FW, FH)), dtype=np.float32) / 255.0


def _dilate(mask, r):
    out = mask.copy()
    for _ in range(r):
        m = out.copy()
        m[1:, :] |= out[:-1, :]
        m[:-1, :] |= out[1:, :]
        m[:, 1:] |= out[:, :-1]
        m[:, :-1] |= out[:, 1:]
        out = m
    return out


def premult(a):
    out = a.copy()
    out[..., :3] *= out[..., 3:4]
    return out


def unpremult(p):
    out = p.copy()
    al = np.maximum(out[..., 3:4], 1e-6)
    out[..., :3] = np.clip(out[..., :3] / al, 0, 1)
    out[..., 3] = np.clip(out[..., 3], 0, 1)
    out[out[..., 3] < 1.0 / 255.0] = 0
    return out


def over(dst, src):
    """src поверх dst, оба — в предумноженной альфе."""
    return src + dst * (1.0 - src[..., 3:4])


def mask_layer(p, mask):
    out = np.zeros_like(p)
    out[mask] = p[mask]
    return out


def transform(p, pivot, angle=0.0, tx=0.0, ty=0.0, sx=1.0, sy=1.0):
    """Поворот по часовой стрелке на angle градусов вокруг pivot, масштаб вокруг него же,
    затем перенос (tx, ty). Билинейная выборка в предумноженной альфе — без тёмных каёмок."""
    h, w = p.shape[:2]
    th = math.radians(angle)
    c, s = math.cos(th), math.sin(th)
    px, py = pivot
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    # обратное отображение: из выходной точки в исходную
    x = xs + 0.5 - px - tx
    y = ys + 0.5 - py - ty
    xr = (c * x + s * y) / sx
    yr = (-s * x + c * y) / sy
    return sample(p, xr + px - 0.5, yr + py - 0.5)


def sample(p, xf, yf):
    h, w = p.shape[:2]
    x0 = np.floor(xf).astype(int)
    y0 = np.floor(yf).astype(int)
    fx = (xf - x0)[..., None]
    fy = (yf - y0)[..., None]

    def at(yy, xx):
        ok = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
        v = p[np.clip(yy, 0, h - 1), np.clip(xx, 0, w - 1)]
        return v * ok[..., None]

    return (at(y0, x0) * (1 - fx) * (1 - fy) + at(y0, x0 + 1) * fx * (1 - fy)
            + at(y0 + 1, x0) * (1 - fx) * fy + at(y0 + 1, x0 + 1) * fx * fy)


def warp_rows(p, row_map, shift_x=None):
    """Построчная деформация: row_map(y_out) -> y_src (дробный), shift_x(y_out) -> сдвиг по x."""
    h, w = p.shape[:2]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    ysrc = np.vectorize(row_map, otypes=[np.float32])(ys[:, 0])[:, None] + np.zeros_like(xs)
    xsrc = xs.copy()
    if shift_x is not None:
        xsrc = xs - np.vectorize(shift_x, otypes=[np.float32])(ys[:, 0])[:, None]
    return sample(p, xsrc, ysrc)


class Doll:
    """Кадр стойки, разрезанный на части."""

    def __init__(self, sheet="idle", index=0):
        a = load_frame(sheet, index)
        self.src = a
        alpha = a[..., 3] > 0.02
        ys, xs = np.mgrid[0:FH, 0:FW]
        p = premult(a)
        self.head = mask_layer(p, alpha & (ys < NECK_Y))
        arm_l = alpha & (xs <= ARM_L_X) & (ys >= ARM_Y0) & (ys <= ARM_Y1)
        arm_r = alpha & (xs >= ARM_R_X) & (ys >= ARM_Y0) & (ys <= ARM_Y1)
        self.arm_l = mask_layer(p, arm_l)
        self.arm_r = mask_layer(p, arm_r)
        skin_l = (xs <= ARM_L_X) & (ys >= ARM_SKIN_Y) & (ys <= ARM_Y1)
        skin_r = (xs >= ARM_R_X) & (ys >= ARM_SKIN_Y) & (ys <= ARM_Y1)
        # Кисти лежат на бёдрах поверх штанин: по цвету кожи вырезаем их (с ободком в 2 точки)
        # из ног и отдаём рукам, а дыру в штанине закрываем продолжением колонки штанины
        # из-под кисти — иначе при поднятой руке кисть остаётся висеть на бедре.
        skin_px = (a[..., 3] > 0.5) & (a[..., 0] > 0.62) & (a[..., 0] - a[..., 2] > 0.14) & (a[..., 1] > 0.42)
        hands = _dilate(skin_px & (ys >= 86) & (ys <= 104) & ((xs <= 64) | (xs >= 78)), 2) & alpha
        hands &= (ys >= 86) & (ys <= 106)
        self.arm_l = mask_layer(p, arm_l | (hands & (xs < 70)))
        self.arm_r = mask_layer(p, arm_r | (hands & (xs >= 70)))
        self.torso = mask_layer(p, alpha & (ys >= NECK_Y) & (ys <= HIP_Y + 3) & ~skin_l & ~skin_r & ~hands)
        legs_src = p.copy()
        fill_row = 108
        hy, hx = np.nonzero(hands & (ys > HIP_Y - 2))
        for y, x in zip(hy, hx):
            legs_src[y, x] = p[fill_row, x]
        # Остатки ободка кисти снаружи штанин (полупрозрачная серая каёмка) — убираем.
        halo = (ys >= 86) & (ys <= 104) & ((xs <= 54) | (xs >= 88))
        legs = alpha & (ys > HIP_Y) & ~halo
        p = legs_src
        self.leg_l = mask_layer(p, legs & (xs <= LEG_SPLIT_X))
        self.leg_r = mask_layer(p, legs & (xs > LEG_SPLIT_X))

    def leg(self, layer, compress=1.0, bulge=0.0, spread=0.0, lift=0.0, shoe_up=0.0):
        """Нога: штанина укорачивается в compress раз (колено идёт вверх), ботинок едет с ней,
        колено выпирает на bulge точек, ступня разведена на spread, всё поднято на lift."""
        thigh = (KNEE_END_Y - HIP_Y)
        new_thigh = thigh * compress

        def row_map(y):
            if y <= HIP_Y:
                return y
            if y <= HIP_Y + new_thigh:
                return HIP_Y + (y - HIP_Y) / compress
            return KNEE_END_Y + (y - HIP_Y - new_thigh)

        def shift(y):
            t = (y - HIP_Y) / max(new_thigh, 1.0)
            if y <= HIP_Y:
                return 0.0
            if y <= HIP_Y + new_thigh:
                return bulge * math.sin(math.pi * t) + spread * t
            return spread

        out = warp_rows(layer, row_map, shift)
        if shoe_up:
            # приподнять только ботинок (постукивание): ступня отдельно от штанины
            shoe = np.zeros_like(out)
            ys = np.mgrid[0:FH, 0:FW][0]
            m = ys >= HIP_Y + new_thigh
            shoe[m] = out[m]
            keep = out.copy()
            keep[m] = 0
            out = over(keep, transform(shoe, (70.0, 126.0), 0, 0, -shoe_up))
        return transform(out, (70.0, 126.0), 0, 0, lift)


def compose(parts):
    out = np.zeros((FH, FW, 4), np.float32)
    for part in parts:
        out = over(out, part)
    return out


def finish(p):
    a = unpremult(p)
    # Альфа: срезаем шум от интерполяции, как у авторских кадров (минимум ~3%).
    a[a[..., 3] < 0.03] = 0
    return a


def face_edit(img, blink=False, shut=False, mouth_open=False, cross=False, shift=(0, 0)):
    """Веки и рот. Лицо — поверх готового кадра, shift — сдвиг головы."""
    a = img.copy()
    dx, dy = shift
    skin = np.array([c / 255.0 for c in SKIN] + [1.0], np.float32)
    lash = np.array([c / 255.0 for c in LASH] + [1.0], np.float32)

    def put(x, y, col):
        xi, yi = int(round(x + dx)), int(round(y + dy))
        if 0 <= xi < FW and 0 <= yi < FH and a[yi, xi, 3] > 0.5:
            a[yi, xi] = col

    if blink or shut:
        for (x0, x1, yl) in ((69, 76, 38), (79, 85, 38)):
            for y in range(36, 41):
                for x in range(x0, x1):
                    put(x, y, skin)
            for x in range(x0, x1):
                for y in ((yl, yl + 1) if shut else (yl,)):
                    put(x, y, lash)
            if shut:
                put(x0, yl - 1, lash)
                put(x1 - 1, yl - 1, lash)
    if cross:
        for (cx, cy) in ((72, 38), (82, 38)):
            for y in range(cy - 3, cy + 4):
                for x in range(cx - 4, cx + 5):
                    put(x, y, skin)
            for k in range(-3, 4):
                for w in (0, 1):
                    put(cx + k + w - 0, cy + k, lash)
                    put(cx + k + w - 0, cy - k, lash)
    if mouth_open:
        for (x, y) in ((72, 45), (73, 45), (74, 45), (75, 45), (72, 46), (73, 46), (74, 46), (75, 46),
                       (73, 47), (74, 47)):
            put(x, y, np.array([0.30, 0.13, 0.12, 1.0], np.float32))
        for (x, y) in ((73, 46), (74, 46)):
            put(x, y, np.array([0.55, 0.18, 0.18, 1.0], np.float32))
    return a


def pose(doll, arm_l=0.0, arm_r=0.0, drop=0.0, head=(0.0, 0.0, 0.0), torso_rot=0.0,
         leg_l=None, leg_r=None, arm_l_lift=0.0, arm_r_lift=0.0, hip_shift=0.0, face=None):
    """Собрать позу. drop — на сколько точек опущено всё выше бёдер (присед);
    head=(угол, dx, dy); torso_rot — наклон корпуса вокруг бёдер; руки: угол вокруг плеча."""
    leg_l = leg_l or {}
    leg_r = leg_r or {}
    hipc = (70.0, HIP_Y)
    upper = []
    h_ang, h_dx, h_dy = head
    head_layer = doll.head
    if face:
        head_layer = premult(face_edit(unpremult(doll.head), **face))
    t_head = transform(head_layer, HEAD_PIVOT, h_ang, h_dx, h_dy)
    t_arm_l = transform(doll.arm_l, SHOULDER_L, arm_l, 0, arm_l_lift)
    t_arm_r = transform(doll.arm_r, SHOULDER_R, arm_r, 0, arm_r_lift)
    body = compose([doll.torso, t_arm_l, t_arm_r, t_head])
    body = transform(body, hipc, torso_rot, hip_shift, drop)
    legs = compose([doll.leg(doll.leg_l, **leg_l), doll.leg(doll.leg_r, **leg_r)])
    return finish(compose([legs, body]))


def build_jump(doll):
    z = []
    # 0 присел: колени вперёд-в стороны, корпус опущен вровень с укороченными ногами
    c = 0.62
    d = (KNEE_END_Y - HIP_Y) * (1 - c)
    z.append(pose(doll, arm_l=14, arm_r=-14, drop=d,
                  leg_l=dict(compress=c, bulge=-5, spread=-2, lift=d),
                  leg_r=dict(compress=c, bulge=5, spread=2, lift=d)))
    # 1 толчок: ноги вместе и вытянуты, руки взмахнули
    z.append(pose(doll, arm_l=38, arm_r=-38, head=(0, 0, -1),
                  leg_l=dict(compress=1.0, spread=1), leg_r=dict(compress=1.0, spread=-1)))
    # 2 подъём: колени идут вверх, руки в стороны
    z.append(pose(doll, arm_l=78, arm_r=-78,
                  leg_l=dict(compress=0.9, bulge=-2, spread=-2), leg_r=dict(compress=0.9, bulge=2, spread=2)))
    # 3 вершина: группировка, руки выше плеч
    z.append(pose(doll, arm_l=108, arm_r=-108,
                  leg_l=dict(compress=0.8, bulge=-3, spread=-3), leg_r=dict(compress=0.8, bulge=3, spread=3)))
    # 4 падение: ноги тянутся вниз, руки вверх-в стороны — балансирует
    z.append(pose(doll, arm_l=128, arm_r=-128, head=(0, 0, 1),
                  leg_l=dict(compress=0.96, spread=-3), leg_r=dict(compress=0.96, spread=3)))
    # 5 быстрое падение: руки вскинуты, ноги шире
    z.append(pose(doll, arm_l=152, arm_r=-152, head=(0, 0, 1),
                  leg_l=dict(compress=1.0, spread=-5), leg_r=dict(compress=1.0, spread=5)))
    # 6 выпрямление: полпути от приседа к стойке
    c2 = 0.82
    d2 = (KNEE_END_Y - HIP_Y) * (1 - c2)
    z.append(pose(doll, arm_l=8, arm_r=-8, drop=d2,
                  leg_l=dict(compress=c2, bulge=-2, lift=d2), leg_r=dict(compress=c2, bulge=2, lift=d2)))
    # 7 вершина, второй такт: руки и колени чуть иначе — на зависании кадры чередуются
    z.append(pose(doll, arm_l=116, arm_r=-100, head=(0, 0, 0),
                  leg_l=dict(compress=0.84, bulge=-2, spread=-2), leg_r=dict(compress=0.78, bulge=3, spread=4)))
    # 8 подъём, ниже: руки на полпути от толчка к горизонтали
    z.append(pose(doll, arm_l=58, arm_r=-58,
                  leg_l=dict(compress=0.95, bulge=-1, spread=-1), leg_r=dict(compress=0.95, bulge=1, spread=1)))
    return z


def build_hurt(doll):
    z = []
    # 0 «ой»: корпус отшатнулся, голова запрокинута, зажмурился, рот открыт, руки врозь
    z.append(pose(doll, arm_l=62, arm_r=-44, head=(11, 3, 1), torso_rot=-5, hip_shift=-1,
                  leg_l=dict(compress=1.0, spread=-3), leg_r=dict(compress=0.9, bulge=2, spread=2),
                  face=dict(shut=True, mouth_open=True)))
    # 1 в отключке: голова свесилась, глаза закрыты, руки плетьми
    z.append(pose(doll, arm_l=16, arm_r=-12, head=(17, 3, 2), torso_rot=3,
                  leg_l=dict(compress=1.0, spread=-1), leg_r=dict(compress=1.0, spread=2),
                  face=dict(cross=True)))
    return z


def build_idle_x(doll):
    z = []
    z.append(pose(doll, face=dict(blink=True)))                             # 0 моргнул
    z.append(pose(doll, head=(6, -2, 0), arm_l=3, arm_r=-2))                # 1 глянул влево
    z.append(pose(doll, head=(-5, 2, 0), arm_l=-2, arm_r=3))                # 2 глянул вправо
    z.append(pose(doll, head=(3, 0, 0), torso_rot=1.2,
                  leg_r=dict(compress=1.0, shoe_up=5.0)))                    # 3 нога вверх
    z.append(pose(doll, head=(2, 0, 1), torso_rot=-0.6, arm_r=-3))           # 4 нога вниз
    return z


def write_sheet(frames, name):
    sheet = np.zeros((FH, FW * len(frames), 4), np.float32)
    for i, f in enumerate(frames):
        sheet[:, i * FW:(i + 1) * FW] = f
    img = Image.fromarray((np.clip(sheet, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    path = os.path.join(CHAR, name)
    img.save(path)
    print(f"{name}: {len(frames)} кадров -> {path}")
    return img


def preview(img, name, outdir, n):
    os.makedirs(outdir, exist_ok=True)
    bg = Image.new("RGBA", img.size, (70, 74, 84, 255))
    bg.alpha_composite(img)
    big = bg.crop((0, 12, img.width, 144)).resize((img.width * 2, 132 * 2), Image.NEAREST)
    big.convert("RGB").save(os.path.join(outdir, name.replace(".png", "_x2.png")))


def main(argv):
    doll = Doll()
    out = {"jump.png": build_jump(doll), "hurt.png": build_hurt(doll), "idle_x.png": build_idle_x(doll)}
    prev = None
    if "--preview" in argv:
        prev = argv[argv.index("--preview") + 1]
    for name, frames in out.items():
        img = write_sheet(frames, name)
        if prev:
            preview(img, name, prev, len(frames))


if __name__ == "__main__":
    main(sys.argv[1:])
