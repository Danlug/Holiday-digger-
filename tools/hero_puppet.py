"""hero_puppet.py — кукла мальчика из частей эталона (для tools/gen_hero_ref.py).

Эталон владельца стоит вполоборота: этого рисунка хватает на стойку, а позы
копки, прыжка, полёта и сна собираются из его же частей — голова, туловище,
две руки (плечо с рукавом и предплечье с кистью), две ноги (бедро и голень с
ботинком). Часть поворачивается вокруг сустава «RotSprite»-способом: рисунок
увеличивается в 4 раза EPX-сглаживанием, поворачивается ближайшим соседом и
уменьшается обратно выбором самого частого цвета в блоке — линии остаются
линиями в один пиксель, новых цветов не появляется. Руки ставятся обратной
кинематикой по точке хвата (рука на рукояти кирки, лопаты, бура, лямке).

Ближняя рука — левая на рисунке (мальчик повернут вправо, к зрителю ближе
его правое плечо), рисуется поверх туловища; дальняя — правая на рисунке,
за туловищем. Где рука ушла с туловища или ног, там дорисовывается то, что
было под ней (продолжение футболки/джинсов по строке), и место разреза
обводится контуром.
"""

import math

import numpy as np
from PIL import Image, ImageDraw

# Суставы на эталоне (родная сетка ref.png).
J = {
    "neck": (80, 102),
    "sh_n": (56, 113), "el_n": (53, 138), "hand_n": (55, 160),
    "sh_f": (98, 115), "el_f": (99, 139), "hand_f": (99, 160),
    "hip_n": (67, 163), "kn_n": (64, 186), "foot_n": (63, 210),
    "hip_f": (88, 163), "kn_f": (89, 186), "foot_f": (92, 210),
}

# Части перекрываются на суставах (локоть, плечо, таз): при повороте на
# стыке не остаётся щели.
UPPER_N = [(46, 103), (63, 102), (63, 127), (61, 128), (61, 140), (44, 140), (44, 110)]
LOWER_N = [(43, 134), (61, 134), (61, 150), (67, 150), (67, 171), (43, 171)]
UPPER_F = [(93, 104), (108, 106), (108, 140), (94, 140), (94, 128), (92, 120)]
LOWER_F = [(94, 134), (110, 134), (110, 171), (90, 171), (90, 150), (94, 150)]
SHOULDER_KEEP = 119   # верх рукавов остаётся и на туловище (круглое плечо)
PELVIS_KEEP = 169     # верх джинсов остаётся и на туловище (таз поверх бёдер)


def _poly_mask(shape, poly):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon(poly, fill=255, outline=255)
    return np.asarray(im) > 0


def _is_skin(c):
    r, g, b = int(c[0]), int(c[1]), int(c[2])
    return r - b > 40 and r > 90


def _lum(img):
    return img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114


def neighbors4(m):
    p = np.pad(m, 1)
    return p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]


def neighbors8(m):
    p = np.pad(m, 1)
    out = np.zeros_like(m)
    for dy in (0, 1, 2):
        for dx in (0, 1, 2):
            if dy == 1 and dx == 1:
                continue
            out |= p[dy:dy + m.shape[0], dx:dx + m.shape[1]]
    return out


# ---------------------------------------------------------------------------
# RotSprite: EPX ×2 ×2 → поворот ближайшим → обратно модой блока 4×4
# ---------------------------------------------------------------------------

def _epx(img):
    h, w = img.shape[:2]
    p = np.pad(img, ((1, 1), (1, 1), (0, 0)))
    c = p[1:-1, 1:-1]
    a = p[:-2, 1:-1]   # верх
    b = p[1:-1, 2:]    # право
    cc = p[1:-1, :-2]  # лево
    d = p[2:, 1:-1]    # низ

    def eq(x, y):
        return (x == y).all(-1)

    out = np.zeros((h * 2, w * 2, 4), img.dtype)
    e1 = np.where((eq(cc, a) & ~eq(cc, d) & ~eq(a, b))[..., None], a, c)
    e2 = np.where((eq(a, b) & ~eq(a, cc) & ~eq(b, d))[..., None], b, c)
    e3 = np.where((eq(d, cc) & ~eq(d, b) & ~eq(cc, a))[..., None], cc, c)
    e4 = np.where((eq(b, d) & ~eq(b, a) & ~eq(d, cc))[..., None], d, c)
    out[0::2, 0::2] = e1
    out[0::2, 1::2] = e2
    out[1::2, 0::2] = e3
    out[1::2, 1::2] = e4
    return out


def _key(img):
    return (img[..., 0].astype(np.int64) << 24) | (img[..., 1].astype(np.int64) << 16) \
        | (img[..., 2].astype(np.int64) << 8) | img[..., 3].astype(np.int64)


def rotate(img, angle_deg, pivot, dest, out_shape):
    """Повернуть img (RGBA) вокруг pivot на угол (плюс — по часовой на экране,
    градусы) и положить pivot в dest на холсте out_shape. Возвращает RGBA холста."""
    k = 4
    oh, ow = out_shape
    out = np.zeros((oh, ow, 4), np.uint8)
    ys, xs = np.nonzero(img[..., 3])
    if len(xs) == 0:
        return out
    # работаем только в рамке части (+1 пиксель на сглаживание EPX)
    x0, y0 = max(0, xs.min() - 1), max(0, ys.min() - 1)
    x1, y1 = min(img.shape[1], xs.max() + 2), min(img.shape[0], ys.max() + 2)
    src = img[y0:y1, x0:x1]
    px, py = pivot[0] - x0, pivot[1] - y0
    big = _epx(_epx(src))
    bh, bw = big.shape[:2]
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    # рамка результата: повёрнутые углы рамки части
    cx = np.array([0, src.shape[1], 0, src.shape[1]]) - px
    cy = np.array([0, 0, src.shape[0], src.shape[0]]) - py
    rx = ca * cx - sa * cy + dest[0]
    ry = sa * cx + ca * cy + dest[1]
    ox0, ox1 = max(0, int(math.floor(rx.min())) - 1), min(ow, int(math.ceil(rx.max())) + 1)
    oy0, oy1 = max(0, int(math.floor(ry.min())) - 1), min(oh, int(math.ceil(ry.max())) + 1)
    if ox1 <= ox0 or oy1 <= oy0:
        return out
    th, tw = (oy1 - oy0) * k, (ox1 - ox0) * k
    yy, xx = np.mgrid[0:th, 0:tw]
    X = (xx + 0.5) / k + ox0 - dest[0]
    Y = (yy + 0.5) / k + oy0 - dest[1]
    sx = (ca * X + sa * Y) + px
    sy = (-sa * X + ca * Y) + py
    bx = np.floor(sx * k).astype(int)
    by = np.floor(sy * k).astype(int)
    ok = (bx >= 0) & (by >= 0) & (bx < bw) & (by < bh)
    rot = np.zeros((th, tw, 4), np.uint8)
    rot[ok] = big[by[ok], bx[ok]]
    # обратно: самый частый цвет в блоке 4×4 (прозрачный, если непрозрачных меньше половины)
    hh, ww = oy1 - oy0, ox1 - ox0
    blocks = rot.reshape(hh, k, ww, k, 4).transpose(0, 2, 1, 3, 4).reshape(hh * ww, k * k, 4)
    keys = _key(blocks)
    opaque = blocks[..., 3] > 0
    same = (keys[:, :, None] == keys[:, None, :]) & opaque[:, None, :]
    cnt = np.where(opaque, same.sum(-1), -1)
    pick = np.argmax(cnt, axis=1)
    res = blocks[np.arange(len(blocks)), pick]
    res[opaque.sum(-1) * 2 < k * k] = 0
    out[oy0:oy1, ox0:ox1] = res.reshape(hh, ww, 4)
    return out


def over(dst, src):
    m = src[..., 3] > 0
    dst[m] = src[m]
    return dst


# ---------------------------------------------------------------------------
# Части эталона
# ---------------------------------------------------------------------------

class Parts:
    def __init__(self, ref):
        self.ref = ref
        h, w = ref.shape[:2]
        a = ref[..., 3] > 0
        lum = _lum(ref.astype(float))
        skin = (ref[..., 0].astype(int) - ref[..., 2] > 40) & (ref[..., 0] > 90) & a
        dark = (lum < 70) & a

        def arm_lower(poly):
            m = _poly_mask(ref.shape, poly) & a
            rows = np.arange(h)[:, None]
            # ниже талии берём только кисть: кожу и контур, касающийся кожи
            low = m & (rows >= 150)
            keep = skin | (dark & neighbors8(skin))
            m = (m & (rows < 150)) | (low & keep)
            return m

        self.mask = {}
        self.mask["lower_n"] = arm_lower(LOWER_N)
        self.mask["upper_n"] = _poly_mask(ref.shape, UPPER_N) & a & ~(self.mask["lower_n"] & (np.arange(h)[:, None] >= 141))
        self.mask["lower_f"] = arm_lower(LOWER_F)
        self.mask["upper_f"] = _poly_mask(ref.shape, UPPER_F) & a & ~(self.mask["lower_f"] & (np.arange(h)[:, None] >= 141))
        arms = self.mask["lower_n"] | self.mask["upper_n"] | self.mask["lower_f"] | self.mask["upper_f"]
        rows = np.arange(h)[:, None] * np.ones((1, w), int)
        cols = np.ones((h, 1), int) * np.arange(w)[None, :]
        self.mask["head"] = a & (rows <= 102) & ~arms
        legs = a & (rows >= 163) & ~arms
        self.mask["thigh_n"] = legs & (cols <= 77) & (rows < 188)
        self.mask["shin_n"] = legs & (cols <= 77) & (rows >= 184)
        self.mask["thigh_f"] = legs & (cols >= 78) & (rows < 188)
        self.mask["shin_f"] = legs & (cols >= 78) & (rows >= 184)
        self.mask["torso"] = a & ~(arms & (rows > SHOULDER_KEEP)) & ~self.mask["head"] \
            & ~(legs & (rows >= PELVIS_KEEP))
        self.layer = {}
        for k, m in self.mask.items():
            lay = np.zeros_like(ref)
            lay[m] = ref[m]
            self.layer[k] = lay
        self.outline = self._outline_color()
        self._fill_under_arms()

    def _outline_color(self):
        a = self.ref[..., 3] > 0
        edge = a & neighbors4(~a)
        cols = self.ref[edge][:, :3]
        lum = _lum(cols.astype(float))
        c = cols[np.argsort(lum)[len(lum) // 4]]
        return np.array([c[0], c[1], c[2], 255], np.uint8)

    def _fill_under_arms(self):
        """Где рука лежала поверх туловища или ног — продолжить их рисунок по строке."""
        for part in ("torso", "thigh_n", "thigh_f"):
            lay = self.layer[part]
            a = lay[..., 3] > 0
            h, w = a.shape
            for y in range(h):
                xs = np.nonzero(a[y])[0]
                if len(xs) < 2:
                    continue
                # дыры внутри строки (между крайними пикселями части)
                for x in range(xs.min(), xs.max() + 1):
                    if not a[y, x]:
                        # ближайший непрозрачный справа и слева
                        r = x + 1
                        while r <= xs.max() and not a[y, r]:
                            r += 1
                        lay[y, x] = lay[y, r] if r <= xs.max() else lay[y, xs.max()]
        self.layer["torso"] = self.layer["torso"]

    # -----------------------------------------------------------------------

    def piece(self, name):
        return self.layer[name]


def ik(shoulder, target, l1, l2, bend):
    """Двузвенная обратная кинематика: углы (рад) плеча и предплечья от
    вертикали вниз. bend = +1/-1 — в какую сторону гнётся локоть."""
    dx = target[0] - shoulder[0]
    dy = target[1] - shoulder[1]
    d = max(1e-3, min(math.hypot(dx, dy), l1 + l2 - 1e-3))
    base = math.atan2(dx, dy)          # 0 — вниз, + — вправо (против часовой в экранных)
    cos_a = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a1 = math.acos(max(-1.0, min(1.0, cos_a)))
    upper = base + bend * a1
    ex = shoulder[0] + l1 * math.sin(upper)
    ey = shoulder[1] + l1 * math.cos(upper)
    lower = math.atan2(target[0] - ex, target[1] - ey)
    return upper, lower, (ex, ey)


def seg_len(p, q):
    return math.hypot(q[0] - p[0], q[1] - p[1])


L_UP_N = seg_len(J["sh_n"], J["el_n"])
L_LO_N = seg_len(J["el_n"], J["hand_n"])
L_UP_F = seg_len(J["sh_f"], J["el_f"])
L_LO_F = seg_len(J["el_f"], J["hand_f"])


def _rest_angle(p, q):
    return math.atan2(q[0] - p[0], q[1] - p[1])


REST = {
    "upper_n": _rest_angle(J["sh_n"], J["el_n"]),
    "lower_n": _rest_angle(J["el_n"], J["hand_n"]),
    "upper_f": _rest_angle(J["sh_f"], J["el_f"]),
    "lower_f": _rest_angle(J["el_f"], J["hand_f"]),
    "thigh_n": _rest_angle(J["hip_n"], J["kn_n"]),
    "shin_n": _rest_angle(J["kn_n"], J["foot_n"]),
    "thigh_f": _rest_angle(J["hip_f"], J["kn_f"]),
    "shin_f": _rest_angle(J["kn_f"], J["foot_f"]),
}


class Pose:
    """Поза куклы. Все углы — от вертикали «вниз», градусы, плюс — вправо
    (кисть уходит вправо, к лицу мальчика). Руки можно задать точкой хвата
    (grip_n / grip_f) — тогда углы считает обратная кинематика."""

    def __init__(self, **kw):
        self.body_dy = kw.get("body_dy", 0)       # корпус ниже/выше (присед)
        self.body_dx = kw.get("body_dx", 0)
        self.lean = kw.get("lean", 0.0)           # наклон корпуса с головой, градусы
        self.head_tilt = kw.get("head_tilt", 0.0)
        self.head_dx = kw.get("head_dx", 0)
        self.head_dy = kw.get("head_dy", 0)
        self.arm_n = kw.get("arm_n")              # (плечо, локоть) градусы или None
        self.arm_f = kw.get("arm_f")
        self.grip_n = kw.get("grip_n")            # точка кисти в координатах эталона
        self.grip_f = kw.get("grip_f")
        self.bend_n = kw.get("bend_n", 1)
        self.bend_f = kw.get("bend_f", -1)
        self.leg_n = kw.get("leg_n")              # (бедро, голень) градусы или None
        self.leg_f = kw.get("leg_f")
        self.face = kw.get("face")                # функция поверх головы (моргание и т. п.)
        self.far_arm_front = kw.get("far_arm_front", False)


def _rot_about(v, pivot, ang):
    """Тот же поворот, что rotate(): плюс — по часовой на экране."""
    ca, sa = math.cos(ang), math.sin(ang)
    x, y = v[0] - pivot[0], v[1] - pivot[1]
    return (pivot[0] + ca * x - sa * y, pivot[1] + sa * x + ca * y)


def render(parts, pose, shape=None, extra_back=None, extra_front=None):
    """Собрать позу на холсте размера эталона. extra_* — функции (canvas,
    joints) для инструмента/снаряжения позади и поверх мальчика."""
    ref = parts.ref
    shape = shape or ref.shape[:2]
    canvas = np.zeros(shape + (4,), np.uint8)
    bx, by = pose.body_dx, pose.body_dy
    lean = math.radians(pose.lean)
    hip_c = ((J["hip_n"][0] + J["hip_f"][0]) / 2.0, J["hip_n"][1])
    # корпус наклоняется вокруг таза: суставы плеч и шеи едут вместе с ним
    def body_pt(p):
        q = _rot_about(p, hip_c, lean)
        return (q[0] + bx, q[1] + by)

    joints = {}
    for k in ("neck", "sh_n", "sh_f"):
        joints[k] = body_pt(J[k])
    joints["hip_n"] = (J["hip_n"][0] + bx, J["hip_n"][1] + by)
    joints["hip_f"] = (J["hip_f"][0] + bx, J["hip_f"][1] + by)

    def leg(side, angles):
        hip = J["hip_" + side]
        kn = J["kn_" + side]
        out = []
        th_rest, sh_rest = REST["thigh_" + side], REST["shin_" + side]
        if angles is None:
            th, sh = th_rest, sh_rest
        else:
            th, sh = math.radians(angles[0]), math.radians(angles[1])
        hip_d = joints["hip_" + side]
        knee_d = (hip_d[0] + seg_len(hip, kn) * math.sin(th), hip_d[1] + seg_len(hip, kn) * math.cos(th))
        out.append(rotate(parts.piece("thigh_" + side), math.degrees(th_rest - th), hip, hip_d, shape))
        out.append(rotate(parts.piece("shin_" + side), math.degrees(sh_rest - sh), kn, knee_d, shape))
        foot_d = (knee_d[0] + seg_len(kn, J["foot_" + side]) * math.sin(sh),
                  knee_d[1] + seg_len(kn, J["foot_" + side]) * math.cos(sh))
        joints["knee_" + side] = knee_d
        joints["foot_" + side] = foot_d
        return out

    def arm(side, angles, grip, bend):
        sh = J["sh_" + side]
        el = J["el_" + side]
        hand = J["hand_" + side]
        l1, l2 = seg_len(sh, el), seg_len(el, hand)
        sh_d = joints["sh_" + side]
        if grip is not None:
            up, lo, eld = ik(sh_d, grip, l1, l2, bend)
        elif angles is not None:
            up, lo = math.radians(angles[0]), math.radians(angles[1])
            eld = (sh_d[0] + l1 * math.sin(up), sh_d[1] + l1 * math.cos(up))
        else:
            up, lo = REST["upper_" + side], REST["lower_" + side]
            eld = (sh_d[0] + l1 * math.sin(up), sh_d[1] + l1 * math.cos(up))
        a_up = rotate(parts.piece("upper_" + side), math.degrees(REST["upper_" + side] - up), sh, sh_d, shape)
        a_lo = rotate(parts.piece("lower_" + side), math.degrees(REST["lower_" + side] - lo), el, eld, shape)
        joints["hand_" + side] = (eld[0] + l2 * math.sin(lo), eld[1] + l2 * math.cos(lo))
        joints["elbow_" + side] = eld
        return a_up, a_lo

    legs_f = leg("f", pose.leg_f)
    legs_n = leg("n", pose.leg_n)
    torso = rotate(parts.piece("torso"), pose.lean, hip_c, (hip_c[0] + bx, hip_c[1] + by), shape)
    head_piv = J["neck"]
    head = rotate(parts.piece("head"), pose.lean + pose.head_tilt, head_piv,
                  (joints["neck"][0] + pose.head_dx, joints["neck"][1] + pose.head_dy), shape)
    if pose.face is not None:
        head = pose.face(head, joints)
    af = arm("f", pose.arm_f, pose.grip_f, pose.bend_f)
    an = arm("n", pose.arm_n, pose.grip_n, pose.bend_n)

    if extra_back:
        extra_back(canvas, joints)
    if not pose.far_arm_front:
        over(canvas, af[0])
        over(canvas, af[1])
    for l in legs_f:
        over(canvas, l)
    for l in legs_n:
        over(canvas, l)
    over(canvas, torso)
    over(canvas, head)
    if pose.far_arm_front:
        over(canvas, af[0])
        over(canvas, af[1])
    over(canvas, an[0])
    over(canvas, an[1])
    if extra_front:
        extra_front(canvas, joints)
    return canvas, joints
